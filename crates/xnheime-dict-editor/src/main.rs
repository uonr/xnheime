use gtk::prelude::*;
use gtk::{gio, glib};
use std::path::PathBuf;
use xnheime_core::{
    append_user_entry, validate_user_entry, UserEntryPlacement, UserEntryValidationError,
};

fn main() -> glib::ExitCode {
    let application = gtk::Application::builder()
        .application_id("io.github.uonr.xnheime.DictEditor")
        .flags(gio::ApplicationFlags::HANDLES_COMMAND_LINE)
        .build();
    let _hold = application.hold();
    let weak_application = application.downgrade();
    let _fcitx_watch = gio::bus_watch_name(
        gio::BusType::Session,
        "org.fcitx.Fcitx5",
        gio::BusNameWatcherFlags::NONE,
        |_, _, _| {},
        move |_, _| {
            if let Some(application) = weak_application.upgrade() {
                application.quit();
            }
        },
    );
    application.connect_command_line(move |application, command_line| {
        let arguments = command_line.arguments();
        let argument = arguments.get(1).and_then(|value| value.to_str());
        if argument == Some("__xnheime_service__") {
            return glib::ExitCode::SUCCESS;
        }
        for window in application.windows() {
            window.close();
        }
        build_window(application, argument.unwrap_or_default());
        glib::ExitCode::SUCCESS
    });
    application.run()
}

fn user_dictionary_directory() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("XDG_DATA_HOME").filter(|path| !path.is_empty()) {
        return Some(PathBuf::from(path).join("xnheime"));
    }
    std::env::var_os("HOME")
        .filter(|path| !path.is_empty())
        .map(|path| PathBuf::from(path).join(".local/share/xnheime"))
}

fn build_window(application: &gtk::Application, initial_code: &str) {
    let window = gtk::ApplicationWindow::builder()
        .application(application)
        .title("新增用户词条")
        .default_width(420)
        .resizable(false)
        .build();
    let content = gtk::Box::new(gtk::Orientation::Vertical, 12);
    content.set_margin_top(18);
    content.set_margin_bottom(18);
    content.set_margin_start(18);
    content.set_margin_end(18);

    let grid = gtk::Grid::builder()
        .row_spacing(10)
        .column_spacing(12)
        .build();
    let code = gtk::Entry::builder()
        .text(initial_code)
        .placeholder_text("最多 4 个编码字符")
        .hexpand(true)
        .build();
    let text = gtk::Entry::builder()
        .placeholder_text("实际要输入的字或词")
        .hexpand(true)
        .build();
    let before = gtk::CheckButton::with_label("系统词库之前");
    let after = gtk::CheckButton::with_label("系统词库之后");
    after.set_group(Some(&before));
    after.set_active(true);
    let placement = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    placement.append(&before);
    placement.append(&after);
    let weight = gtk::Entry::builder()
        .placeholder_text("可选，例如 100")
        .hexpand(true)
        .build();
    code.set_activates_default(true);
    text.set_activates_default(true);
    weight.set_activates_default(true);

    attach_row(&grid, 0, "编码", &code);
    attach_row(&grid, 1, "字词", &text);
    attach_row(&grid, 2, "位置", &placement);
    attach_row(&grid, 3, "权重", &weight);
    content.append(&grid);

    let error = gtk::Label::builder().xalign(0.0).wrap(true).build();
    error.add_css_class("error");
    content.append(&error);

    let buttons = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    buttons.set_halign(gtk::Align::End);
    let cancel = gtk::Button::with_label("取消");
    let submit = gtk::Button::with_label("保存");
    submit.add_css_class("suggested-action");
    buttons.append(&cancel);
    buttons.append(&submit);
    content.append(&buttons);
    window.set_child(Some(&content));
    window.set_default_widget(Some(&submit));

    let key_controller = gtk::EventControllerKey::new();
    let weak_window = window.downgrade();
    key_controller.connect_key_pressed(move |_, key, _, _| {
        if key == gtk::gdk::Key::Escape {
            if let Some(window) = weak_window.upgrade() {
                window.close();
            }
            return glib::Propagation::Stop;
        }
        glib::Propagation::Proceed
    });
    window.add_controller(key_controller);

    let weak_window = window.downgrade();
    cancel.connect_clicked(move |_| {
        if let Some(window) = weak_window.upgrade() {
            window.close();
        }
    });

    let weak_window = window.downgrade();
    let submit_weight = weight.clone();
    let submit_text = text.clone();
    submit.connect_clicked(move |_| {
        let placement = if before.is_active() {
            UserEntryPlacement::BeforeSystem
        } else {
            UserEntryPlacement::AfterSystem
        };
        let entry = match validate_user_entry(
            &code.text(),
            &submit_text.text(),
            placement,
            &submit_weight.text(),
        ) {
            Ok(entry) => entry,
            Err(validation_error) => {
                error.set_text(validation_message(validation_error));
                return;
            }
        };
        let Some(directory) = user_dictionary_directory() else {
            error.set_text("无法确定用户数据目录：HOME 和 XDG_DATA_HOME 均未设置。");
            return;
        };
        if let Err(write_error) = append_user_entry(&directory, &entry) {
            error.set_text(&format!("无法写入 xnhe.txt：{write_error}"));
            return;
        }
        if let Some(window) = weak_window.upgrade() {
            window.close();
        }
    });

    after.connect_toggled(move |button| weight.set_sensitive(button.is_active()));
    window.present();
    text.grab_focus();
}

fn attach_row(grid: &gtk::Grid, row: i32, title: &str, widget: &impl IsA<gtk::Widget>) {
    let label = gtk::Label::new(Some(title));
    label.set_halign(gtk::Align::End);
    grid.attach(&label, 0, row, 1, 1);
    grid.attach(widget, 1, row, 1, 1);
}

fn validation_message(error: UserEntryValidationError) -> &'static str {
    match error {
        UserEntryValidationError::InvalidCode => "编码必须是 1–4 个小写字母、分号或单引号。",
        UserEntryValidationError::InvalidText => "字词不能为空，也不能包含 Tab 或换行。",
        UserEntryValidationError::InvalidWeight => "权重必须留空或填写数字。",
    }
}
