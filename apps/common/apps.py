from django.apps import AppConfig
from django.contrib import admin

class CommonConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.common'

    def ready(self):
        # Customize admin site
        admin.site.site_header = "Administration"
        admin.site.site_title = "Admin Panel"
        admin.site.index_title = "Welcome to Admin Panel"