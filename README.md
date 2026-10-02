# PuppyPay Helper APK

Installed on pool UPI phones. Reads payment notifications and reports to backend for auto order approval.

## Flow
1. Admin panel → Devices → Create device → copy **Device Code**
2. Install this APK on the UPI phone
3. Enter Device Code → Connect
4. Enable **Notification Access**
5. Keep app running (disable battery optimization)

## API
- `POST /api/device/connect`
- `POST /api/device/heartbeat`
- `POST /api/device/payment`
- `POST /api/device/disconnect`
