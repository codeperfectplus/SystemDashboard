import os
import datetime
from flask import render_template, request, flash, blueprints, redirect, url_for

from src.config import app, db
from src.models import UserCardSettings, UserDashboardSettings, UserProfile, GeneralSettings, PageToggleSettings
from flask_login import login_required, current_user
from src.utils import render_template_from_file, ROOT_DIR
from src.scripts.email_me import send_smtp_email
from src.routes.helper import get_email_addresses
from src.config import get_app_info

settings_bp = blueprints.Blueprint("settings", __name__)

@app.route('/settings/speedtest', methods=['GET', 'POST'])
@login_required
def user_settings():
    user_dashboard_settings = UserDashboardSettings.query.filter_by(user_id=current_user.id).first()  # Retrieve user-specific settings from DB
    if request.method == 'POST':
        user_dashboard_settings.speedtest_cooldown = request.form.get('speedtest_cooldown')
        user_dashboard_settings.number_of_speedtests = request.form.get('number_of_speedtests')
        user_dashboard_settings.refresh_interval = request.form.get('refresh_interval')
        db.session.commit()
        flash('Speedtest settings updated successfully!', 'success')
        return redirect(url_for('user_settings'))
    return render_template('settings/user_settings.html', user_dashboard_settings=user_dashboard_settings)

@app.route('/settings/general', methods=['GET', 'POST'])
@login_required
def general_settings():
    # Retrieve user-specific settings from DB
    general_settings = GeneralSettings.query.filter_by().first()
    # Store the current state of the 'enable_alerts' setting
    current_alert_status = general_settings.enable_alerts
    if request.method == 'POST':
        # Update the settings from the form
        general_settings.timezone = request.form.get('timezone')
        general_settings.enable_cache = 'enable_cache' in request.form
        general_settings.enable_alerts = 'enable_alerts' in request.form
        general_settings.is_logging_system_info = 'is_logging_system_info' in request.form

        # Check if the 'enable_alerts' status has changed
        if current_alert_status != general_settings.enable_alerts:
            # If 'enable_alerts' was changed, send an email to the admins
            admin_emails_with_alerts = get_email_addresses(user_level="admin", receive_email_alerts=True)
            if admin_emails_with_alerts:
                subject = f"{get_app_info()['title']} Alert Status Changed"
                context = {
                    "current_time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "notifications_enabled": general_settings.enable_alerts,
                    "current_user": current_user.username,
                    "title": get_app_info()["title"],
                }
                notification_alert_template = os.path.join(ROOT_DIR, "src/templates/email_templates/notification_alert.html")
                email_body = render_template_from_file(notification_alert_template, **context)
                
                # Send email only if 'enable_alerts' changed
                send_smtp_email(admin_emails_with_alerts, subject, email_body, is_html=True, bypass_alerts=True)
        # Save the updated settings to the database
        db.session.commit()
        flash('General settings updated successfully!', 'success')
        return redirect(url_for('general_settings'))

    return render_template('settings/general_settings.html', general_settings=general_settings)

@app.route('/settings/page-toggles', methods=['GET', 'POST'])
@login_required
def feature_toggles():
    page_toggles_settings = PageToggleSettings.query.filter_by(user_id=current_user.id).first()  # Retrieve user-specific settings from DB
    if request.method == 'POST':
        # is_dashboard_network_enabled
        page_toggles_settings.is_dashboard_network_enabled = 'is_dashboard_network_enabled' in request.form
        page_toggles_settings.is_cpu_info_enabled = 'is_cpu_info_enabled' in request.form
        page_toggles_settings.is_memory_info_enabled = 'is_memory_info_enabled' in request.form
        page_toggles_settings.is_disk_info_enabled = 'is_disk_info_enabled' in request.form
        page_toggles_settings.is_network_info_enabled = 'is_network_info_enabled' in request.form
        page_toggles_settings.is_process_info_enabled = 'is_process_info_enabled' in request.form
        db.session.commit()
        flash('Feature toggles updated successfully!', 'success')
        return redirect(url_for('feature_toggles'))
    return render_template('settings/page_toggles.html', page_toggles_settings=page_toggles_settings)

@app.route('/settings/card-toggles', methods=['GET', 'POST'])
@login_required
def card_toggles():
    card_settings = UserCardSettings.query.filter_by(user_id=current_user.id).first()  # Retrieve user-specific settings from DB
    if request.method == 'POST':
        card_settings.is_user_card_enabled = 'is_user_card_enabled' in request.form
        card_settings.is_server_card_enabled = 'is_server_card_enabled' in request.form
        card_settings.is_battery_card_enabled = 'is_battery_card_enabled' in request.form
        card_settings.is_cpu_core_card_enabled = 'is_cpu_core_card_enabled' in request.form
        card_settings.is_cpu_usage_card_enabled = 'is_cpu_usage_card_enabled' in request.form
        card_settings.is_cpu_temp_card_enabled = 'is_cpu_temp_card_enabled' in request.form
        card_settings.is_dashboard_memory_card_enabled = 'is_dashboard_memory_card_enabled' in request.form
        card_settings.is_memory_usage_card_enabled = 'is_memory_usage_card_enabled' in request.form
        card_settings.is_disk_usage_card_enabled = 'is_disk_usage_card_enabled' in request.form
        card_settings.is_system_uptime_card_enabled = 'is_system_uptime_card_enabled' in request.form
        card_settings.is_network_statistic_card_enabled = 'is_network_statistic_card_enabled' in request.form
        card_settings.is_speedtest_enabled = 'is_speedtest_enabled' in request.form
        db.session.commit()
        flash('Card toggles updated successfully!', 'success')
        return redirect(url_for('card_toggles'))
    return render_template('settings/card_toggles.html', card_settings=card_settings)

@app.route("/settings", methods=["GET", "POST"])
@login_required
def settings():
    if current_user.user_level != 'admin':
        flash("Your account does not have permission to view this page.", "danger")
        flash("User level for this account is: " + current_user.user_level, "danger")
        flash("Please contact your administrator for more information.", "danger")
        return render_template("error/403.html")

    return render_template("settings/settings.html", settings=settings)
