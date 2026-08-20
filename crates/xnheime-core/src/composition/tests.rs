use super::{
    CompositionEffect as Effect, CompositionEvent as Event, CompositionMode, CompositionSession,
    DictionaryMode, DispatchContext, CANDIDATES_PER_ROW,
};
use chrono::{FixedOffset, TimeZone};
use compact_str::CompactString;
use std::fs;

fn fixed_time() -> DispatchContext {
    let timezone = FixedOffset::east_opt(9 * 60 * 60).unwrap();
    DispatchContext {
        now: timezone
            .with_ymd_and_hms(2026, 8, 18, 14, 3, 0)
            .single()
            .unwrap(),
        selected_text: None,
        clipboard_text: None,
        dictionary_mode: DictionaryMode::Expert,
    }
}

#[test]
fn converts_and_commits_candidates() {
    let mut session = CompositionSession::new();
    let effects = session.dispatch(Event::InputText { text: "n".into() });
    assert!(
        matches!(effects.as_slice(), [Effect::SetMarkedText { text }, Effect::ShowCandidates { .. }] if text == "n")
    );
    let effects = session.dispatch(Event::InputText { text: "i".into() });
    assert!(
        matches!(effects.as_slice(), [Effect::SetMarkedText { text }, Effect::ShowCandidates { .. }] if text == "ni")
    );
    let effects = session.dispatch(Event::InputText { text: " ".into() });
    assert_eq!(
        effects,
        vec![
            Effect::InsertText { text: "你".into() },
            Effect::HideCandidates
        ]
    );
    assert_eq!(session.mode(), CompositionMode::Idle);
}

#[test]
fn user_dictionary_layers_surround_the_system_dictionary() {
    let directory = std::env::temp_dir().join(format!(
        "xnheime-user-dictionary-test-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    fs::create_dir_all(&directory).unwrap();
    fs::write(
        directory.join("xnhe.txt"),
        "置顶词\tni # top\n居后词\tni\n高权重\tzzzz\t9\n低权重\tzzzz\t1\n",
    )
    .unwrap();

    let mut session = CompositionSession::new();
    let result = session.load_user_dictionary_directory(&directory).unwrap();
    assert_eq!(result.loaded_entries, 4);
    session.dispatch(Event::InputText { text: "n".into() });
    session.dispatch(Event::InputText { text: "i".into() });
    let candidates: Vec<_> = session
        .candidates()
        .into_iter()
        .map(|candidate| CompactString::new(candidate.text()))
        .collect();
    assert_eq!(candidates.first().map(AsRef::as_ref), Some("置顶词"));
    assert_eq!(candidates.last().map(AsRef::as_ref), Some("居后词"));

    let _ = fs::remove_dir_all(directory);
}

#[test]
fn invalid_continuation_and_shift_enter_inline() {
    let mut session = CompositionSession::new();
    session.dispatch(Event::InputText { text: "g".into() });
    session.dispatch(Event::InputText { text: "i".into() });
    assert_eq!(
        session.dispatch(Event::InputText { text: "t".into() }),
        vec![
            Effect::SetMarkedText { text: "git".into() },
            Effect::ShowCandidates {
                candidates: vec![super::CandidateItem::ActionHint {
                    text: "新增".into(),
                    label: "+".into(),
                    action: super::CandidateAction::AddUserEntry,
                }]
                .into(),
                selected_index: 0,
                character_index: 3,
            }
        ]
    );
    session.dispatch(Event::EnterInline { text: "H".into() });
    assert_eq!(session.mode(), CompositionMode::Inline);
    assert_eq!(
        session.dispatch(Event::Commit),
        vec![
            Effect::InsertText {
                text: "gitH".into()
            },
            Effect::HideCandidates
        ]
    );
}

#[test]
fn plus_requests_user_entry_for_converting_and_empty_codes() {
    let mut session = CompositionSession::new();
    session.dispatch(Event::InputText { text: "n".into() });
    session.dispatch(Event::InputText { text: "i".into() });
    assert!(!session.candidates().is_empty());
    assert_eq!(
        session.dispatch(Event::InputText { text: "+".into() }),
        vec![Effect::ShowAddEntryDialog { code: "ni".into() }]
    );

    session.dispatch(Event::Cancel {
        clear_marked_text: false,
    });
    for text in ["g", "i", "t"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    assert_eq!(session.mode(), CompositionMode::Inline);
    assert_eq!(
        session.dispatch(Event::InputText { text: "+".into() }),
        vec![Effect::ShowAddEntryDialog { code: "git".into() }]
    );
}

#[test]
fn plus_remains_text_in_explicit_inline_ascii() {
    let mut session = CompositionSession::new();
    session.dispatch(Event::InputText { text: "n".into() });
    session.dispatch(Event::EnterInline { text: "H".into() });
    assert_eq!(
        session.dispatch(Event::InputText { text: "+".into() }),
        vec![
            Effect::SetMarkedText { text: "nH+".into() },
            Effect::HideCandidates,
        ]
    );
}

#[test]
fn continuing_after_matched_four_key_code_commits_then_starts_new_code() {
    let mut session = CompositionSession::new();
    for text in ["b", "i", "r", "u"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    assert_eq!(session.candidates()[0].text(), "比如");

    let effects = session.dispatch(Event::InputText { text: "n".into() });
    assert!(matches!(
        effects.as_slice(),
        [
            Effect::InsertText { text: committed },
            Effect::HideCandidates,
            Effect::SetMarkedText { text: following },
            Effect::ShowCandidates { .. }
        ] if committed == "比如" && following == "n"
    ));
    assert!(matches!(session.mode(), CompositionMode::Converting { .. }));
}

#[test]
fn apostrophe_is_contextual() {
    let mut session = CompositionSession::new();
    assert_eq!(
        session.dispatch(Event::InputText { text: "'".into() }),
        vec![Effect::InsertText { text: "‘".into() }]
    );
    assert_eq!(
        session.dispatch(Event::InputText { text: "'".into() }),
        vec![Effect::InsertText { text: "’".into() }]
    );
    for text in ["a", "o", "f"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    let effects = session.dispatch(Event::InputText { text: "'".into() });
    assert!(
        matches!(effects.as_slice(), [Effect::SetMarkedText { text }, Effect::ShowCandidates { .. }] if text == "aof'")
    );
}

#[test]
fn punctuation_matches_chinese_input_conventions() {
    let mut session = CompositionSession::new();
    for (input, output) in [
        ("\\", "、"),
        ("{", "「"),
        ("}", "」"),
        ("^", "……"),
        ("_", "——"),
    ] {
        assert_eq!(
            session.dispatch(Event::InputText { text: input.into() }),
            vec![Effect::InsertText {
                text: output.into()
            }]
        );
    }
    for punctuation in ["/", "|", "~", "@", "#", "$", "%", "&", "*", "+"] {
        assert_eq!(
            session.dispatch(Event::InputText {
                text: punctuation.into()
            }),
            vec![Effect::InsertText {
                text: punctuation.into()
            }]
        );
    }
}

#[test]
fn left_fast_symbols_insert_pairs_and_right_symbols_remain_single() {
    for (code, before, after) in [
        (";q", "：“", "”"),
        (";e", "（", "）"),
        (";y", "《", "》"),
        (";o", "[", "]"),
        (";h", "[", "]"),
        (";k", "(", ")"),
        (";z", "“", "”"),
    ] {
        let mut session = CompositionSession::new();
        for character in code.chars() {
            session.dispatch(Event::InputText {
                text: character.to_string(),
            });
        }
        assert_eq!(
            session.dispatch(Event::Commit),
            vec![
                Effect::InsertPairedText {
                    before: before.into(),
                    after: after.into(),
                },
                Effect::HideCandidates,
            ],
            "{code}"
        );
    }

    let mut session = CompositionSession::new();
    for character in ";r".chars() {
        session.dispatch(Event::InputText {
            text: character.to_string(),
        });
    }
    assert_eq!(
        session.dispatch(Event::Commit),
        vec![
            Effect::InsertText { text: "）".into() },
            Effect::HideCandidates,
        ]
    );
}

#[test]
fn history_repeats_the_complete_inserted_pair() {
    let mut session = CompositionSession::new();
    for character in ";e".chars() {
        session.dispatch(Event::InputText {
            text: character.to_string(),
        });
    }
    session.dispatch(Event::Commit);
    for character in ";f".chars() {
        session.dispatch(Event::InputText {
            text: character.to_string(),
        });
    }
    assert_eq!(session.candidates()[0].text(), "（）");
}

#[test]
fn selects_second_candidate_and_commits_code() {
    let mut session = CompositionSession::new();
    for text in ["o", "x", "y"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    let second = CompactString::new(session.candidates()[1].text());
    assert_eq!(
        session.dispatch(Event::InputText { text: ";".into() }),
        vec![Effect::InsertText { text: second }, Effect::HideCandidates]
    );

    for text in ["o", "x", "y"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    assert_eq!(
        session.dispatch(Event::CommitCode),
        vec![
            Effect::InsertText { text: "oxy".into() },
            Effect::HideCandidates
        ]
    );
}

#[test]
fn deletion_recovers_conversion_from_inline() {
    let mut session = CompositionSession::new();
    for text in ["g", "i", "t"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    assert_eq!(session.mode(), CompositionMode::Inline);
    let effects = session.dispatch(Event::InputText {
        text: "\u{7f}".into(),
    });
    assert!(
        matches!(effects.as_slice(), [Effect::SetMarkedText { text }, Effect::ShowCandidates { .. }] if text == "gi")
    );
    assert!(matches!(session.mode(), CompositionMode::Converting { .. }));
}

#[test]
fn wildcard_candidates_include_their_codes() {
    let mut session = CompositionSession::new();
    assert_eq!(
        session.dispatch(Event::InputText { text: "`".into() }),
        vec![Effect::InsertText { text: "`".into() }]
    );
    session.dispatch(Event::InputText { text: "n".into() });
    session.dispatch(Event::InputText { text: "`".into() });
    assert!(session
        .candidates()
        .iter()
        .all(|candidate| candidate.code().is_some()));
}

#[test]
fn wildcard_candidates_put_single_han_characters_first() {
    assert_eq!(super::candidates::wildcard_candidate_category("南"), 0);
    assert_eq!(super::candidates::wildcard_candidate_category("南京"), 1);
    assert_eq!(super::candidates::wildcard_candidate_category("hello"), 2);

    let mut session = CompositionSession::new();
    session.dispatch(Event::InputText { text: "n".into() });
    session.dispatch(Event::InputText { text: "`".into() });

    let categories: Vec<_> = session
        .candidates()
        .iter()
        .map(|candidate| super::candidates::wildcard_candidate_category(candidate.text()))
        .collect();
    assert!(categories.contains(&0));
    assert!(categories.windows(2).all(|pair| pair[0] <= pair[1]));
}

#[test]
fn row_navigation_and_number_selection_use_the_selected_row() {
    let mut session = CompositionSession::new();
    session.dispatch(Event::InputText { text: "n".into() });
    session.dispatch(Event::InputText { text: "`".into() });
    let candidates = session.candidates();
    assert!(candidates.len() > CANDIDATES_PER_ROW);

    session.dispatch(Event::MoveCandidate {
        offset: CANDIDATES_PER_ROW as i32,
    });
    assert_eq!(
        session.dispatch(Event::InputText { text: "1".into() }),
        vec![
            Effect::InsertText {
                text: CompactString::new(candidates[CANDIDATES_PER_ROW].text())
            },
            Effect::HideCandidates
        ]
    );
}

#[test]
fn history_repeats_only_the_last_committed_candidate() {
    let mut session = CompositionSession::new();
    for text in ["n", "i", " "] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &fixed_time());
    }
    for text in [";", "f"] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &fixed_time());
    }
    assert_eq!(session.candidates()[0].text(), "你");

    session.dispatch_with_context(Event::CommitCode, &fixed_time());
    for text in [";", "f"] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &fixed_time());
    }
    assert_eq!(session.candidates()[0].text(), "你");
}

#[test]
fn date_and_time_translators_use_the_dispatch_time_snapshot() {
    let mut session = CompositionSession::new();
    for text in ["o", "r", "q"] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &fixed_time());
    }
    assert_eq!(
        session
            .candidates()
            .into_iter()
            .map(|candidate| CompactString::new(candidate.text()))
            .collect::<Vec<_>>(),
        ["2026年08月18日", "2026-08-18"]
    );

    session.dispatch_with_context(
        Event::Cancel {
            clear_marked_text: false,
        },
        &fixed_time(),
    );
    for text in ["o", "u", "j"] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &fixed_time());
    }
    assert_eq!(
        session
            .candidates()
            .into_iter()
            .map(|candidate| CompactString::new(candidate.text()))
            .collect::<Vec<_>>(),
        ["14:03", "1787029380"]
    );
}

#[test]
fn clipboard_translator_lists_codes_in_character_order() {
    let mut session = CompositionSession::new();
    let mut context = fixed_time();
    context.clipboard_text = Some("你好你A".into());
    for text in ["o", "f", "i"] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &context);
    }
    let candidates = session.candidates();
    assert_eq!(
        candidates.first().map(|candidate| candidate.text()),
        Some("你")
    );
    assert!(candidates
        .iter()
        .any(|candidate| { candidate.text() == "你" && candidate.code() == Some("ni") }));
    assert!(candidates.iter().any(|candidate| candidate.text() == "好"));
    assert_eq!(
        candidates
            .iter()
            .filter(|candidate| candidate.text() == "你" && candidate.code() == Some("ni"))
            .count(),
        1
    );
    assert!(!candidates.iter().any(|candidate| candidate.text() == "A"));
}

#[test]
fn clipboard_translator_falls_back_to_last_committed_candidate() {
    let mut session = CompositionSession::new();
    let context = fixed_time();
    for text in ["n", "i", " "] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &context);
    }

    let mut unsuitable_clipboard = fixed_time();
    unsuitable_clipboard.clipboard_text = Some("ASCII 123".into());
    for text in ["o", "f", "i"] {
        session.dispatch_with_context(
            Event::InputText { text: text.into() },
            &unsuitable_clipboard,
        );
    }

    assert!(session
        .candidates()
        .iter()
        .any(|candidate| { candidate.text() == "你" && candidate.code() == Some("ni") }));
}

#[test]
fn selected_text_takes_priority_over_clipboard_and_history() {
    let mut session = CompositionSession::new();
    let mut context = fixed_time();
    context.selected_text = Some("好".into());
    context.clipboard_text = Some("你".into());
    for text in ["o", "f", "i"] {
        session.dispatch_with_context(Event::InputText { text: text.into() }, &context);
    }
    let candidates = session.candidates();
    assert!(candidates.iter().all(|candidate| candidate.text() == "好"));
    assert!(!candidates.is_empty());
}

#[test]
fn cancel_clears_marked_text_when_requested() {
    let mut session = CompositionSession::new();
    session.dispatch(Event::InputText { text: "n".into() });
    assert_eq!(
        session.dispatch(Event::Cancel {
            clear_marked_text: true
        }),
        vec![
            Effect::HideCandidates,
            Effect::SetMarkedText { text: "".into() },
        ]
    );
    assert_eq!(session.mode(), CompositionMode::Idle);
}

fn merged_session(keys: &[&str]) -> (CompositionSession, Vec<Effect>) {
    let mut session = CompositionSession::new();
    let mut effects = Vec::new();
    for key in keys {
        effects = session.dispatch(Event::InputMergedKey {
            letters: (*key).into(),
        });
    }
    (session, effects)
}

fn marked_text(effects: &[Effect]) -> Option<String> {
    effects.iter().find_map(|effect| match effect {
        Effect::SetMarkedText { text } => Some(text.to_string()),
        _ => None,
    })
}

fn candidate_codes(session: &CompositionSession) -> Vec<(String, String)> {
    session
        .candidates()
        .iter()
        .map(|candidate| {
            (
                candidate.text().to_string(),
                candidate.code().unwrap_or_default().to_string(),
            )
        })
        .collect()
}

#[test]
fn merged_keys_offer_every_reading_with_its_own_code() {
    let (session, _) = merged_session(&["qw", "op"]);
    let candidates = candidate_codes(&session);
    assert_eq!(
        candidates,
        vec![
            ("群殴".into(), "qo".into()),
            ("且".into(), "qp".into()),
            ("我".into(), "wo".into()),
            ("网盘".into(), "wp".into()),
        ]
    );
}

#[test]
fn touch_weight_reorders_merged_candidates_without_removing_readings() {
    let mut session = CompositionSession::new();
    session.dispatch(Event::InputWeightedMergedKey {
        letters: "bn".into(),
        primary_weight: 100,
    });
    session.dispatch(Event::InputMergedKey {
        letters: "i".into(),
    });

    let candidates = candidate_codes(&session);
    assert_eq!(
        candidates.first().map(|(_, code)| code.as_str()),
        Some("ni")
    );
    assert!(candidates.iter().any(|(_, code)| code == "bi"));
}

#[test]
fn resolved_and_merged_keys_mix_position_by_position() {
    let (session, _) = merged_session(&["qw", "o"]);
    assert_eq!(
        candidate_codes(&session),
        vec![("群殴".into(), "qo".into()), ("我".into(), "wo".into())]
    );

    let (session, _) = merged_session(&["w", "op"]);
    assert_eq!(
        candidate_codes(&session),
        vec![("我".into(), "wo".into()), ("网盘".into(), "wp".into())]
    );

    let (session, _) = merged_session(&["qw", "w"]);
    assert_eq!(
        candidate_codes(&session),
        vec![("千万".into(), "qw".into()), ("为".into(), "ww".into())]
    );

    let (session, _) = merged_session(&["w", "o"]);
    assert_eq!(
        candidate_codes(&session),
        vec![("我".into(), String::new())]
    );
}

#[test]
fn resolving_keys_narrows_a_four_key_code() {
    let counts: Vec<usize> = [
        ["as", "as", "jk", "jk"],
        ["a", "as", "jk", "jk"],
        ["a", "a", "jk", "k"],
        ["a", "a", "k", "k"],
    ]
    .iter()
    .map(|keys| merged_session(keys).0.candidates().len())
    .collect();
    assert_eq!(counts, vec![5, 3, 2, 1]);
}

#[test]
fn merged_code_shows_the_selected_candidate_code_as_marked_text() {
    let (mut session, effects) = merged_session(&["qw", "op"]);
    assert_eq!(marked_text(&effects).as_deref(), Some("qo"));

    let effects = session.dispatch(Event::MoveCandidate { offset: 2 });
    assert_eq!(marked_text(&effects).as_deref(), Some("wo"));

    let effects = session.dispatch(Event::CommitCode);
    assert_eq!(
        effects,
        vec![
            Effect::InsertText { text: "wo".into() },
            Effect::HideCandidates
        ]
    );
}

#[test]
fn selecting_an_absolute_candidate_commits_in_one_event() {
    let (mut session, _) = merged_session(&["n"]);
    let expected = session.candidates()[1].text().to_owned();
    let effects = session.dispatch(Event::SelectCandidate { index: 1 });
    assert_eq!(
        effects,
        vec![
            Effect::InsertText {
                text: expected.into()
            },
            Effect::HideCandidates
        ]
    );
    assert_eq!(session.mode(), super::CompositionMode::Idle);
}

#[test]
fn selecting_an_invalid_absolute_candidate_does_nothing() {
    let (mut session, _) = merged_session(&["n", "i"]);
    assert!(session
        .dispatch(Event::SelectCandidate { index: u32::MAX })
        .is_empty());
    assert!(matches!(
        session.mode(),
        super::CompositionMode::Converting { .. }
    ));
}

#[test]
fn unambiguous_codes_keep_their_marked_text_and_bare_candidates() {
    let (mut session, effects) = merged_session(&["n", "i"]);
    assert_eq!(marked_text(&effects).as_deref(), Some("ni"));
    let effects = session.dispatch(Event::MoveCandidate { offset: 1 });
    assert!(marked_text(&effects).is_none());
}

#[test]
fn a_single_letter_merged_key_matches_plain_input() {
    let mut merged = CompositionSession::new();
    let mut plain = CompositionSession::new();
    for (letter, expected) in [("n", "n"), ("i", "ni")] {
        let merged_effects = merged.dispatch(Event::InputMergedKey {
            letters: letter.into(),
        });
        let plain_effects = plain.dispatch(Event::InputText {
            text: letter.into(),
        });
        assert_eq!(merged_effects, plain_effects);
        assert_eq!(marked_text(&merged_effects).as_deref(), Some(expected));
    }
}

#[test]
fn deleting_a_merged_key_keeps_the_remaining_ambiguity() {
    let (mut session, _) = merged_session(&["qw", "op"]);
    session.dispatch(Event::InputText {
        text: "\u{7f}".into(),
    });
    let codes: Vec<String> = candidate_codes(&session)
        .into_iter()
        .map(|(_, code)| code)
        .collect();
    assert!(codes.iter().any(|code| code == "q"));
    assert!(codes.iter().any(|code| code == "w"));
}

#[test]
fn merged_keys_are_literal_while_typing_inline_ascii() {
    let mut session = CompositionSession::new();
    session.dispatch(Event::InputText { text: "n".into() });
    session.dispatch(Event::EnterInline { text: "W".into() });
    let effects = session.dispatch(Event::InputMergedKey {
        letters: "op".into(),
    });
    assert_eq!(marked_text(&effects).as_deref(), Some("nWo"));
    assert_eq!(session.mode(), CompositionMode::Inline);
}

#[test]
fn a_fifth_merged_key_commits_and_starts_a_new_code() {
    let (mut session, _) = merged_session(&["qw", "qw", "qw", "qw"]);
    let committed = session.candidates()[0].text().to_string();
    let effects = session.dispatch(Event::InputMergedKey {
        letters: "bn".into(),
    });
    assert_eq!(
        effects.first(),
        Some(&Effect::InsertText {
            text: committed.into()
        })
    );
    assert!(matches!(session.mode(), CompositionMode::Converting { .. }));
    assert!(candidate_codes(&session)
        .iter()
        .any(|(_, code)| code == "n"));
}

#[test]
fn convenience_dispatch_uses_the_session_dictionary_mode() {
    let mut session = CompositionSession::new();
    session.set_dictionary_mode(DictionaryMode::Beginner);
    for text in ["a", "o", "f", "e"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    assert!(session
        .candidates()
        .iter()
        .any(|candidate| candidate.text() == "嶅"));
}

#[test]
fn ok_mode_accepts_codes_longer_than_normal_flypy_codes() {
    let mut session = CompositionSession::new();
    for text in ["o", "k", "h", "g", "u", "u"] {
        session.dispatch(Event::InputText { text: text.into() });
    }
    assert!(session
        .candidates()
        .iter()
        .any(|candidate| candidate.text() == "丁"));
}
