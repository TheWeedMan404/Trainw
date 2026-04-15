# TRAINW Hardware Integration

## Endpoint

- URL: `https://<your-project>.supabase.co/functions/v1/gate-checkin`
- Method: `POST`
- Headers:
  - `Content-Type: application/json`
  - `apikey: <SUPABASE_ANON_KEY>` for browser kiosk calls
  - `Authorization: Bearer <token>` is optional for the gate terminal flow

## Common Response

Every request returns JSON with the same top-level contract:

```json
{
  "access": true,
  "client_name": "Sana Ben Ali",
  "days_left": 12
}
```

Denied example:

```json
{
  "access": false,
  "reason": "membership_expired"
}
```

The hardware controller only needs to check `access`.

## Payloads

### QR

```json
{
  "type": "qr",
  "gym_id": "GYM_UUID",
  "device_id": "gate-1",
  "token": "CLIENT_UUID.GYM_UUID.random.signature"
}
```

### RFID Card

```json
{
  "type": "rfid_card",
  "gym_id": "GYM_UUID",
  "device_id": "gate-1",
  "credential_data": "04A2248B91"
}
```

### Fingerprint

```json
{
  "type": "fingerprint",
  "gym_id": "GYM_UUID",
  "device_id": "gate-1",
  "credential_data": "FP-TEMPLATE-0142"
}
```

### Face

```json
{
  "type": "face",
  "gym_id": "GYM_UUID",
  "device_id": "gate-1",
  "credential_data": "FACE-PROFILE-7781"
}
```

## Enrollment Flow

1. Register the member on the hardware first.
2. Copy the hardware UID or template ID into TRAINW from the `Badges & Biométrie` tab.

## Notes

- `credential_data` is only the hardware identifier.
- Actual biometric image or template data is never sent to Supabase.
- Every access attempt is written to `gate_access_log`.
- Successful hardware validations also create a `check_ins` row for attendance.
