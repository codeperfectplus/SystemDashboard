
from src.config import db

class UserDashboardSettings(db.Model):
    """
    User dashboard settings model for the application
    ---
    Properties:
        - id: int
        - user_id: the user id
        - speedtest_cooldown: the cooldown for speedtests
        - number_of_speedtests: the number of speedtests
        - refresh_interval: the refresh interval for the dashboard
    """
    __tablename__ = 'user_dashboard_settings'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'))
    speedtest_cooldown = db.Column(db.Integer, default=60)
    number_of_speedtests = db.Column(db.Integer, default=1)
    refresh_interval = db.Column(db.Integer, default=0)
    bytes_to_megabytes = db.Column(db.Integer, default=1000)
    
