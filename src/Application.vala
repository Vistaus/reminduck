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

using Gee;

namespace Reminduck {

    public class ReminduckApp : Gtk.Application {

        construct {
            application_id = "com.github.matfantinel.reminduck";
            flags = ApplicationFlags.HANDLES_COMMAND_LINE;
            database = new Reminduck.Database();
        }

        public static ArrayList<Reminder> reminders;
        public bool headless = false;
        private uint timeout_id = 0;

        public MainWindow main_window { get; private set; default = null; }
        public static Reminduck.Database database;

        public static int main(string[] args) {
            var app = new ReminduckApp();

            if (args.length > 1 && args[1] == "--headless") {
                app.headless = true;
            }

            return app.run(args);
        }

        protected override void activate() {
            stdout.printf("\n✔️ Activated");
            database.verify_database();

            var settings = new GLib.Settings("com.github.matfantinel.reminduck.state");

            var first_run = settings.get_boolean("first-run");

            if (first_run) {
                stdout.printf("\n🎉️ First run");
                install_autostart();
                settings.set_boolean("first-run", false);
            }
            
            reload_reminders();

            if (this.main_window == null) {
                this.main_window = new MainWindow();
                this.main_window.set_application(this);                
                                
                var provider = new Gtk.CssProvider();
                provider.load_from_resource("/com/github/matfantinel/reminduck/stylesheet.css");
                Gtk.StyleContext.add_provider_for_screen(
                    Gdk.Screen.get_default(),
                    provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );

                if (!this.headless) {
                    this.main_window.show_all();
                    this.main_window.show_welcome_view(Gtk.StackTransitionType.NONE);
                    this.main_window.present();
                }
            }
            
            if (this.main_window != null && !this.headless) {
                this.main_window.show_all();
                this.main_window.show_welcome_view(Gtk.StackTransitionType.NONE);
                this.main_window.present();
            }

            if (timeout_id == 0) {
                set_reminder_interval();
            }
        }  
        
        public override int command_line(ApplicationCommandLine command_line) {
            stdout.printf("\n💲️ Command line mode started");
    
            bool headless_mode = false;
            OptionEntry[] options = new OptionEntry[1];
            options[0] = {
                "headless", 0, 0, OptionArg.NONE,
                ref headless_mode, "Run without window", null
            };
    
            // We have to make an extra copy of the array, since .parse assumes
            // that it can remove strings from the array without freeing them.
            string[] args = command_line.get_arguments();
            string[] _args = new string[args.length];
            for(int i = 0; i < args.length; i++) {
                _args[i] = args[i];
            }
    
            try {
                var ctx = new OptionContext();
                ctx.set_help_enabled(true);
                ctx.add_main_entries(options, null);
                unowned string[] tmp = _args;
                ctx.parse(ref tmp);
            } catch(OptionError e) {
                command_line.print("error: %s\n", e.message);
                return 0;
            }
    
            this.headless = headless_mode;

            stdout.printf(this.headless ? "\n✔️ Headless" : "\n️️️️ ✔️ Interface");
    
            hold();
            activate();
            return 0;
        }                

        private void install_autostart() {
            var desktop_file_name = application_id + ".desktop";
            var desktop_file_path = new DesktopAppInfo(desktop_file_name).filename;
            var desktop_file = File.new_for_path(desktop_file_path);
            var dest_path = Path.build_path(
                Path.DIR_SEPARATOR_S,
                Environment.get_user_config_dir(),
                "autostart",
                desktop_file_name
            );
            var dest_file = File.new_for_path(dest_path);
            try {
                desktop_file.copy(dest_file, FileCopyFlags.OVERWRITE);
                stdout.printf("\n📃️ Copied desktop file at: %s", dest_path);
            } catch(Error e) {
                warning("Error making copy of desktop file for autostart: %s", e.message);
            }
    
            var keyfile = new KeyFile();
            try {
                keyfile.load_from_file(dest_path, KeyFileFlags.NONE);
                keyfile.set_boolean("Desktop Entry", "X-GNOME-Autostart-enabled", true);
                keyfile.set_string("Desktop Entry", "Exec", application_id + " --headless");
                keyfile.save_to_file(dest_path);
            } catch(Error e) {
                warning("Error enabling autostart: %s", e.message);
            }
        }

        public static void reload_reminders() {
            reminders = database.fetch_reminders();
        }

        public void set_reminder_interval() {
            // Disable old timer to avoid repeated notifications
            if (timeout_id > 0) {
                Source.remove(timeout_id);
            }

            timeout_id = Timeout.add_seconds(1 * 60, remind);
        }
    
        public bool remind() {
            reload_reminders();
            
            var reminders_to_delete = new ArrayList<string>();
            foreach(var reminder in reminders) {
                //If reminder date < current date
                if (reminder.time.compare(new GLib.DateTime.now()) <= 0) {
                    var notification = new Notification("QUACK!");
                    notification.set_body(reminder.description);
                    notification.set_priority(GLib.NotificationPriority.URGENT);
                    this.send_notification("notify.app", notification);

                    if (reminder.recurrency_type != RecurrencyType.NONE) {
                        GLib.DateTime new_time = reminder.time;

                        //In case the user hasn't used his computer for a while, recurrent reminders
                        //May have not fired for a while. Instead of bombarding him with notifications,
                        //Let's make sure our new date is in the future

                        //Let's try it only 30 times - no need to risk an infinite loop
                        for (var i = 0; i < 30; i++) {
                            switch (reminder.recurrency_type) {
                                case RecurrencyType.EVERY_X_MINUTES:
                                    new_time = reminder.time.add_minutes(reminder.recurrency_interval);
                                    break;
                                case RecurrencyType.EVERY_DAY:
                                    new_time = reminder.time.add_days(1);
                                    break;
                                case RecurrencyType.EVERY_WEEK:
                                    new_time = reminder.time.add_weeks(1);
                                    break;
                                case RecurrencyType.EVERY_MONTH:
                                    new_time = reminder.time.add_months(1);
                                    break;
                                default:
                                    break;
                            }

                            //if new_time > current time
                            if (new_time.compare(new GLib.DateTime.now()) > 0) {
                                var new_reminder = new Reminder();
                                new_reminder.time = new_time;
                                new_reminder.description = reminder.description;
                                new_reminder.recurrency_type = reminder.recurrency_type;

                                database.upsert_reminder(new_reminder);
                                break;
                            }
                            //else, keep looping
                        }
                    }

                    reminders_to_delete.add(reminder.rowid);
                }
            }

            if (reminders_to_delete.size > 0) {
                foreach(var reminder in reminders_to_delete) {
                    database.delete_reminder(reminder);
                }
                reload_reminders();
            }

            return true;
        }
    }
}