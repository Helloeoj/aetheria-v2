"""Account identity and authoritative, revisioned character storage."""
import uuid
from django.db import models


class Account(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    username = models.CharField(max_length=20)
    username_key = models.CharField(max_length=20, unique=True)
    password_hash = models.CharField(max_length=256)
    email = models.EmailField(null=True, blank=True)
    email_verified_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class Character(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    account = models.OneToOneField(Account, on_delete=models.CASCADE)
    revision = models.PositiveBigIntegerField(default=0)
    state = models.JSONField(default=dict)
    lease_generation = models.PositiveBigIntegerField(default=0)
    lease_hash = models.CharField(max_length=64, blank=True)
    lease_world = models.CharField(max_length=80, blank=True)
    lease_expires_at = models.DateTimeField(null=True)
    updated_at = models.DateTimeField(auto_now=True)


class Session(models.Model):
    token_hash = models.CharField(max_length=64, primary_key=True)
    account = models.ForeignKey(Account, on_delete=models.CASCADE)
    expires_at = models.DateTimeField(db_index=True)


class Admission(models.Model):
    token_hash = models.CharField(max_length=64, primary_key=True)
    session = models.ForeignKey(Session, on_delete=models.CASCADE)
    world_id = models.CharField(max_length=80)
    expires_at = models.DateTimeField(db_index=True)
    consumed = models.BooleanField(default=False)


class Journal(models.Model):
    character = models.ForeignKey(Character, on_delete=models.CASCADE)
    operation_id = models.UUIDField()
    payload_hash = models.CharField(max_length=64)
    lease_hash = models.CharField(max_length=64)
    lease_generation = models.PositiveBigIntegerField()
    revision = models.PositiveBigIntegerField()
    state = models.JSONField()
    released = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['character', 'operation_id'], name='unique_character_operation')]


class RateLimit(models.Model):
    key = models.CharField(max_length=64, primary_key=True)
    window = models.BigIntegerField()
    count = models.PositiveIntegerField(default=0)
