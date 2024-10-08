from src.routes.cpu_info import cpu_info_bp
from src.routes.disk_info import disk_info_bp
from src.routes.dashboard import dashboard_bp
from src.routes.memory_info import memory_info_bp
from src.routes.network_info import network_info_bp
from src.routes.settings import settings_bp
from src.routes.speedtest import speedtest_bp
from src.routes.process_info import process_bp
from src.routes.auth import auth_bp
from src.routes.dashboard_network import network_bp
from src.routes.other import other_bp
from src.routes.smtp_email_config import smtp_email_config_bp
from src.routes.user_management import user_management_bp
from src.routes.graphs import graphs_bp
from src.routes.ping import ping_bp
from src.routes.firewall import firewall_bp
from src.routes.health import health_bp
from src.routes.api import api_bp
from src.routes.experimental import experimental_bp
from src.routes.error_handlers import error_handlers_bp
from src.routes.profile import profile_bp
from src.routes.prometheus import prometheus_bp
from src.routes.alert_route import alert_bp
from src.routes.update_webhooks import webhooks_bp

__all__ = [
    "cpu_info_bp",
    "disk_info_bp",
    "dashboard_bp",
    "memory_info_bp",
    "network_info_bp",
    "settings_bp",
    "speedtest_bp",
    "process_bp",
    "auth_bp",
    "network_bp",
    "other_bp",
    "smtp_email_config_bp",
    "user_management_bp",
    "graphs_bp",
    "ping_bp",
    "firewall_bp",
    "health_bp",
    "api_bp",
    "experimental_bp",
    "error_handlers_bp",
    "profile_bp",
    "prometheus_bp",
    "alert_bp",
    "webhooks_bp",
]