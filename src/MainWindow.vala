/*
* Copyright(c) 2011-2019 Matheus Fantinel
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or(at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Matheus Fantinel <matfantinel@gmail.com>
*/

namespace Reminduck {
    public class MainWindow : Gtk.ApplicationWindow {
        Gtk.Stack stack;
        Gtk.HeaderBar headerbar;
        Gtk.Button back_button;

        private GLib.Settings settings;

        Granite.Placeholder welcome_widget = null;
        int? view_reminders_action_reference = null;

        Widgets.Views.ReminderEditor reminder_editor;
        Widgets.Views.RemindersView reminders_view;

        public MainWindow() {
            settings = new GLib.Settings("io.github.ellie_commons.reminduck.state");

            build_ui();
        }

        private void build_ui() {
            stack = new Gtk.Stack();
            stack.set_transition_duration(500);

            this.build_headerbar();
            
            this.build_welcome();
            
            var image = new Gtk.Image();
            image.set_from_icon_name("io.github.ellie_commons.reminduck");
            image.set_margin_top(30);

            var fields_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            fields_box.add_css_class("reminduck-welcome-box");
            fields_box.append(image);
            fields_box.append(this.welcome_widget);

            stack.add_named(fields_box, "welcome");

            this.build_reminder_editor();
            this.build_reminders_view();

            set_child(stack);            

            this.show_welcome_view(Gtk.StackTransitionType.NONE);

            delete_event.connect(e => {
                return before_destroy();
            });
        }        

        private void build_headerbar() {
            this.headerbar = new Gtk.HeaderBar();
            this.headerbar.show_close_button = true;
            this.headerbar.title = "Reminduck";
            this.headerbar.add_css_class("default-decoration");
            this.headerbar.add_css_class("reminduck-headerbar");
            set_titlebar(this.headerbar);

            this.back_button = new Gtk.Button.with_label(_("Back"));
            this.back_button.add_css_class("back-button");
            this.back_button.valign = Gtk.Align.CENTER;
            this.headerbar.pack_start(this.back_button);
            
            this.back_button.clicked.connect(() => {
                this.show_welcome_view();                
            });                        
        }

        private void build_welcome() {
            this.welcome_widget = new Granite.Placeholder(_("QUACK! I'm Reminduck") {
                description = _("The duck that reminds you")
            };

            this.welcome_widget.activated.connect((index) => {
                switch(index) {
                    case 0:
                        show_reminder_editor();
                        break;
                    case 1:
                        show_reminders_view(Gtk.StackTransitionType.SLIDE_LEFT);
                        break;
                }
            });

            this.welcome_widget.add("document-new", _("New Reminder"), _("Create a new reminder for a set date and time"));
            if (ReminduckApp.reminders.size > 0) {
                this.view_reminders_action_reference = this.welcome_widget.append("accessories-text-editor", _("View Reminders"), _("See reminders you've created"));
            }
        }

        private void update_view_reminders_welcome_action() {
            if (ReminduckApp.reminders.size > 0) {
                if (this.view_reminders_action_reference == null) {
                    this.view_reminders_action_reference = this.welcome_widget.append("accessories-text-editor", _("View Reminders"), _("See reminders you've created"));
                    this.welcome_widget.show();
                }
            } else {
                if (this.view_reminders_action_reference != null) {
                    this.welcome_widget.remove_item(this.view_reminders_action_reference);
                }
                this.view_reminders_action_reference = null;
            }
        }

        private void build_reminder_editor() {
            this.reminder_editor = new Widgets.Views.ReminderEditor();

            this.reminder_editor.reminder_created.connect((new_reminder) => {
                ReminduckApp.reload_reminders();                
                show_reminders_view();
            });

            this.reminder_editor.reminder_edited.connect((edited_file) => {
                ReminduckApp.reload_reminders();
                show_reminders_view();
            });

            stack.add_named(this.reminder_editor, "reminder_editor");
        }

        private void build_reminders_view() {
            this.reminders_view = new Widgets.Views.RemindersView();

            this.reminders_view.add_request.connect(() => {
                show_reminder_editor();
            });

            this.reminders_view.edit_request.connect((reminder) => {
                show_reminder_editor(reminder);
            });

            this.reminders_view.reminder_deleted.connect(() => {
                ReminduckApp.reload_reminders();
                if (ReminduckApp.reminders.size == 0) {
                    show_welcome_view();
                } else {
                    this.reminders_view.build_reminders_list();
                }
            });

            stack.add_named(this.reminders_view, "reminders_view");
        }

        private void show_reminder_editor(Reminder? reminder = null) {
            stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT);
            stack.set_visible_child_name("reminder_editor");
            this.back_button.show();
            this.reminder_editor.edit_reminder(reminder);
        }

        private void show_reminders_view(Gtk.StackTransitionType slide = Gtk.StackTransitionType.SLIDE_RIGHT) {
            stack.set_transition_type(slide);
            stack.set_visible_child_name("reminders_view");
            this.reminders_view.build_reminders_list();
            this.back_button.show();
            this.reminder_editor.reset_fields();
        }

        public void show_welcome_view(Gtk.StackTransitionType slide = Gtk.StackTransitionType.SLIDE_RIGHT) {
            this.update_view_reminders_welcome_action();
            stack.set_transition_type(slide);
            stack.set_visible_child_name("welcome");
            this.back_button.hide();
            this.reminder_editor.reset_fields();
        }

        private bool before_destroy() {
            int width, height;

            get_default_size(out width, out height);
    
            this.settings.set_int("window-width", width);
            this.settings.set_int("window-height", height);
    
            hide();
            return true;
        }
    }
}
