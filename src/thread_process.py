import datetime
from threading import Timer
from src.config import app, db
from src.utils import get_system_info_for_db
from src.logger import logger
from src.models import MonitoredWebsite, ApplicationGeneralSettings, SystemInformation
from sqlalchemy.exc import SQLAlchemyError
import requests


def monitor_settings():
    """
    Monitors application general settings for changes and controls system logging dynamically.
    This function runs periodically to check for updates to logging settings.
    """
    with app.app_context():
        try:
            # Fetch the general settings
            general_settings = ApplicationGeneralSettings.query.first()

            # Check if logging should be active or not
            is_logging_system_info = general_settings.is_logging_system_info if general_settings else False
            if is_logging_system_info:
                logger.info("System logging enabled. Starting system info logging.")
                Timer(0, log_system_info).start()
            else:
                logger.info("System logging disabled. Stopping system info logging.")

            # Check settings periodically (every 10 seconds)
            Timer(10, monitor_settings).start()

        except SQLAlchemyError as db_err:
            logger.error(f"Error fetching settings: {db_err}", exc_info=True)


def log_system_info():
    """
    Logs system information at regular intervals based on the general settings.
    This function checks if logging is still active before each logging event.
    """
    with app.app_context():
        try:
            # Fetch the general settings to check if logging is enabled
            general_settings = ApplicationGeneralSettings.query.first()
            is_logging_system_info = general_settings.is_logging_system_info if general_settings else False

            if not is_logging_system_info:
                logger.info("System info logging has been stopped.")
                return

            log_system_info_to_db()
            logger.debug("System information logged successfully.")

            # Schedule the next log after 60 seconds
            Timer(60, log_system_info).start()

        except Exception as e:
            logger.error(f"Error during system info logging: {e}", exc_info=True)


def log_system_info_to_db():
    """
    Fetches system information and logs it to the database.
    """
    with app.app_context():
        try:
            system_info = get_system_info_for_db()
            system_log = SystemInformation(
                cpu_percent=system_info["cpu_percent"],
                memory_percent=system_info["memory_percent"],
                battery_percent=system_info["battery_percent"],
                network_sent=system_info["network_sent"],
                network_received=system_info["network_received"],
                timestamp=datetime.datetime.now()
            )
            db.session.add(system_log)
            db.session.commit()
            logger.info("System information logged to database.")

        except SQLAlchemyError as db_err:
            logger.error(f"Database error while logging system info: {db_err}", exc_info=True)
            db.session.rollback()
        except Exception as e:
            logger.error(f"Failed to log system information: {e}", exc_info=True)


def ping_website(website):
    """
    Pings a single website and updates its status in the database.
    """
    with app.app_context():
        try:
            # Check if the website is still active
            updated_website = MonitoredWebsite.query.get(website.id)
            if not updated_website or not updated_website.is_ping_active:
                logger.info(f"Website {website.name} is no longer active. Stopping monitoring.")
                return

            logger.info(f"Pinging {website.name} (Interval: {website.ping_interval}s)...")
            response = requests.get(website.name, timeout=10)
            updated_website.last_ping_time = datetime.datetime.now()
            updated_website.ping_status_code = response.status_code

            if response.status_code == 200:
                updated_website.ping_status = 'UP'
                logger.info(f"{website.name} is UP.")
            else:
                updated_website.ping_status = 'DOWN'
                logger.warning(f"{website.name} is DOWN with status code {response.status_code}.")
            
            db.session.commit()
            logger.info(f"Website {website.name} updated successfully.")

        except requests.RequestException as req_err:
            updated_website.ping_status = 'DOWN'
            logger.error(f"Failed to ping {website.name}: {req_err}", exc_info=True)
            db.session.rollback()

        except SQLAlchemyError as db_err:
            logger.error(f"Database commit error for {website.name}: {db_err}", exc_info=True)
            db.session.rollback()

        finally:
            # Add more detailed logging for debugging
            if db.session.new or db.session.dirty:
                logger.warning(f"Database transaction not committed properly for {website.name}.")
            
            # Schedule the next ping for this website
            Timer(updated_website.ping_interval, ping_website, args=[updated_website]).start()


def start_website_monitoring():
    """
    Periodically pings monitored websites based on individual ping intervals.
    """
    with app.app_context():
        try:
            while True:
                active_websites = MonitoredWebsite.query.filter_by(is_ping_active=True).all()
                if not active_websites:
                    logger.info("No active websites to monitor.")
                else:
                    for website in active_websites:
                        # Start pinging each website individually based on its ping interval
                        Timer(0, ping_website, args=[website]).start()
                
                # Check for active websites periodically (every 30 seconds)
                Timer(30, start_website_monitoring).start()
                break  # Break out of the loop to avoid creating a new thread infinitely

        except SQLAlchemyError as db_err:
            logger.error(f"Database error during website monitoring: {db_err}", exc_info=True)
        except Exception as e:
            logger.error(f"Error during website monitoring: {e}", exc_info=True)


