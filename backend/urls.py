from django.urls import re_path
from backend.accounts.views import endpoint

urlpatterns = [re_path(r'^(?P<route>.*?)/?$', endpoint)]
