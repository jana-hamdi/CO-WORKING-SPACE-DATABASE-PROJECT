# 🏢 Co-Working Space Booking System — Database

> A fully normalized relational database for managing co-working space operations: room bookings (individual & group), employee shift tracking, payments, lost & found, and a product store.

---

## 📁 Repository Structure

```
co-working-space-database/
│
├── README.md                        ← You are here
│
├── schema/
│   └── CO-WORKING_SPACE_DATABASE.sqlnb   ← Full Oracle SQL schema + seed data
│
├── docs/
│   ├── ERD.pdf                      ← Entity-Relationship Diagram (visual)
│   ├── MAPPING.pdf                  ← Relational table mapping (attribute-level)
│   └── ERD_Technical_Analysis.PDF   ← Full technical analysis report (business rules, constraints, enums)
```

---

## 🗄️ Database Overview

This database models the complete lifecycle of a co-working space management system, built on **Oracle SQL**. It covers:

| Domain | Tables Involved |
|---|---|
| Space configuration | `WORKSPACE`, `ROOM`, `AMENITY`, `ROOM_AMENITY` |
| Individual bookings | `INDIVIDUAL_BOOKING`, `CUSTOMER_USER` |
| Group bookings | `GROUP_BOOKING`, `CUSTOMER_USER` |
| Payments | `PAYMENT` |
| Staff & scheduling | `EMPLOYEE`, `SHIFT` |
| Lost & found | `LOST_FOUND` |
| Product store | `PRODUCT`, `STORE_ORDER`, `ORDER_ITEM` |

---

## 🧱 Entity Catalogue

### WORKSPACE
Top-level operational unit. Stores all system-wide configurable parameters.

| Column | Type | Notes |
|---|---|---|
| `WorkspaceID` | NUMBER(5) PK | Surrogate key |
| `WorkspaceName` | VARCHAR2(100) | NOT NULL |
| `GracePeriodMinutes` | NUMBER(3) | Default: 30 |
| `CancellationThresholdHours` | NUMBER(2) | Default: 2 |
| `DepositRatePercent` | NUMBER(3) | Default: 25 |
| `TaxRatePercent` | NUMBER(5,2) | Default: 14.00 |
| `DepositPaymentWindowMinutes` | NUMBER(3) | Default: 15 |

---

### ROOM
A physical room within a workspace. Type is either `Individual` or `Group` (BR-01-001).

| Column | Type | Notes |
|---|---|---|
| `RoomID` | NUMBER(5) PK | |
| `WorkspaceID` | NUMBER(5) FK | → WORKSPACE |
| `RoomName` | VARCHAR2(100) | |
| `PrimaryType` | VARCHAR2(10) | ENUM: `Individual` \| `Group` |
| `BaseHourlyPrice` | NUMBER(10,2) | |
| `Capacity` | NUMBER(3) | Must be > 0 |
| `IsActive` | CHAR(1) | `Y` / `N` |

---

### AMENITY & ROOM_AMENITY
Features attached to rooms (e.g., Wi-Fi, Projector, PlayStation). Each room must have at least one amenity (BR-01-002). The `ROOM_AMENITY` junction resolves the M:M relationship.

---

### CUSTOMER_USER
Customers who make bookings. Identity is defined by `FullName + PhoneNumber` (unique composite key).

| Column | Type | Notes |
|---|---|---|
| `UserID` | NUMBER(5) PK | |
| `FullName` | VARCHAR2(100) | |
| `PhoneNumber` | VARCHAR2(20) | |
| `Email` | VARCHAR2(100) | Optional |

---

### INDIVIDUAL_BOOKING
Single-seat reservation for an individual room. No end time is set at creation — duration is computed at checkout.

Key fields: `UserID`, `RoomID`, `Channel` (`Online`/`Walk-In`), `Status`, `PriceSnapshot`, `GracePeriodExpiry`, `CheckInTime`, `CheckOutTime`, `TotalAmount`.

Three separate employee FKs track creation, check-in, and check-out staff (BR-07-003).

**Status lifecycle:** `Pending` → `Checked-In` → `Checked-Out` | `Auto-Cancelled` | `Cancelled`

> Walk-in bookings skip `Pending` and begin directly at `Checked-In` (BR-04-002).

---

### GROUP_BOOKING
Full-room reservation with a pre-scheduled time window and upfront deposit.

Key fields: `RoomID`, `ScheduledStart`, `ScheduledEnd`, `DepositAmount`, `DepositPaid`, `CancellationThresholdSnapshot`, `PriceSnapshot`, `TotalAmount`, `TaxAmount`.

**Billing formula:**  
`Deposit = BasePrice × BookedDuration × 25%`  
`FinalBill = (BasePrice × BookedDuration) − Deposit + Taxes`

**Status lifecycle:** `Pending` → `Confirmed` → `Checked-In` → `Completed` | `Cancelled-Refunded` | `Cancelled-Forfeited` | `No-Show`

---

### PAYMENT
Financial transaction linked to either an individual or group booking.

| Column | Notes |
|---|---|
| `Method` | ENUM: `Cash` \| `Credit Card` \| `InstaPay` |
| `PaymentType` | ENUM: `Deposit` \| `Balance` \| `Full` |
| `IsRefunded` | Tracks deposit refunds on valid group cancellations |

---

### EMPLOYEE & SHIFT
Staff members and their scheduled time windows. Shifts for the same employee on the same date must not overlap (BR-07-001).

---

### LOST_FOUND
Logs items found on premises. Four fields are mandatory at entry: `Description`, `RoomID`, `FoundAt`, `LoggedByEmpID` (BR-08-001).

**Status lifecycle:** `Found` → `Stored` → `Claimed` | `Disposed`

---

### PRODUCT, STORE_ORDER & ORDER_ITEM
A self-contained store sub-system. A single shared catalogue serves both online and on-site channels. `ORDER_ITEM` is the junction/line-item table resolving the M:M between orders and products.

---

## 🔗 Relationships Summary

| Entity A | Entity B | Cardinality | Notes |
|---|---|---|---|
| WORKSPACE | ROOM | 1:M | |
| ROOM | AMENITY | M:M | via ROOM_AMENITY |
| ROOM | INDIVIDUAL_BOOKING | 1:M | |
| ROOM | GROUP_BOOKING | 1:M | |
| CUSTOMER_USER | INDIVIDUAL_BOOKING | 1:M | |
| INDIVIDUAL_BOOKING | PAYMENT | 1:M | |
| GROUP_BOOKING | PAYMENT | 1:M | |
| EMPLOYEE | SHIFT | 1:M | |
| EMPLOYEE | INDIVIDUAL_BOOKING | 1:M ×3 | Creation / Check-In / Check-Out |
| EMPLOYEE | GROUP_BOOKING | 1:M ×3 | Creation / Check-In / Check-Out |
| ROOM | LOST_FOUND | 1:M | |
| STORE_ORDER | PRODUCT | M:M | via ORDER_ITEM |
| CUSTOMER_USER | STORE_ORDER | 1:M (optional) | Nullable FK; guest orders allowed |

---

## ⚙️ Key Business Rules & Constraints

| Rule ID | Type | Description |
|---|---|---|
| BR-01-001 | CHECK | Room `PrimaryType` must be exactly one of `{Individual, Group}` |
| BR-01-002 | CHECK | Each room must have at least one entry in `ROOM_AMENITY` |
| BR-02-001 | BUSINESS | Price/Capacity changes are prospective only; existing bookings retain snapshot values |
| BR-02-002 | BLOCK | Room type cannot change while active bookings exist |
| BR-03-001 | ENFORCE | Group booking stays `Pending` until deposit is recorded |
| BR-03-003 | BUSINESS | Deposit refund only if cancellation is before the threshold; No-shows forfeit unconditionally |
| BR-04-002 | ENFORCE | Walk-in individual bookings skip `Pending`, begin at `Checked-In` |
| BR-04-004 | BLOCK | No two active individual bookings for the same user may overlap |
| BR-05-002 | BLOCK | No two confirmed group bookings for the same room may overlap |
| BR-05-003 | ENFORCE | Group bookings not checked in by `ScheduledStart` are auto-marked `No-Show` |
| BR-07-001 | CHECK | No two shifts for the same employee on the same date may overlap |
| BR-07-002 | AUDIT | Every booking must reference the active `ShiftID` and `EmployeeID` at creation |
| BR-08-001 | NOT NULL | Lost & Found entries require: Description, RoomID, FoundAt, LoggedByEmpID |
| BR-09-002 | CHECK | Products with `StockQuantity = 0` or `IsActive = N` are unpurchasable |
| BR-09-005 | ENFORCE | `StockQuantity` is shared across channels and decremented atomically |
| SYS-02 | ENFORCE | `PriceSnapshot` is immutable after booking creation |

---

## 📐 Design Decisions

**No ROOM_TYPE table** — Room type (`Individual`/`Group`) is stored directly as `PrimaryType` in the `ROOM` table, simplifying joins while keeping the discriminator constraint clean.

**Three-role employee pattern** — Both `INDIVIDUAL_BOOKING` and `GROUP_BOOKING` carry three separate employee FKs (`EmpID_Creation`, `EmpID_CheckIn`, `EmpID_CheckOut`) to support full audit traceability when different staff handle different stages of a booking.

**Price snapshot enforcement** — `PriceSnapshot` on each booking stores the rate at creation time. This satisfies BR-02-001 and SYS-02, ensuring price changes never retroactively affect confirmed bookings.

**Availability as a derived concept** — `AvailableSeats` is not stored. It is computed as:  
`AvailableSeats = Capacity − COUNT(Checked-In) − COUNT(Pending within grace period)`

**Store independence** — `STORE_ORDER` and `ORDER_ITEM` form a self-contained sub-system linked to the rest of the schema only via a nullable `UserID` FK (for guest orders).

---

## 🚀 Getting Started

This schema targets **Oracle SQL** (tested on Oracle 19c+). To run it:

1. Open the `.sqlnb` file in **Oracle SQL Developer** or any compatible Oracle SQL client.
2. Execute the DDL section (Section 1 — `CREATE TABLE` statements) to build the schema.
3. Execute the sequences section (Section 2) to create auto-increment sequences.
4. Optionally run the seed data section (Section 3 — `INSERT` statements) to populate sample data.
5. Run the SELECT queries in Section 4 to verify the setup.

```sql
-- Quick verification after setup
SELECT RoomID, RoomName, PrimaryType, BaseHourlyPrice, Capacity, IsActive
FROM ROOM
ORDER BY PrimaryType, RoomName;
```

---

## 📄 Documentation

| File | Description |
|---|---|
| `docs/ERD.pdf` | Full Entity-Relationship Diagram showing all entities, attributes, and cardinality |
| `docs/MAPPING.pdf` | Relational table mapping with PK/FK annotations for every table |
| `docs/ERD_Technical_Analysis.PDF` | Comprehensive analyst report: entity catalogue, relationship table, constraint list, enum domains, and ERD construction notes |

---

## 🛠️ Tech Stack

- **Database:** Oracle SQL (Oracle 19c+)
- **Sequences:** Oracle native sequences for surrogate key generation
- **Constraints:** CHECK, NOT NULL, UNIQUE, FOREIGN KEY enforced at the DDL level
- **Notebook format:** `.sqlnb` (Oracle SQL Developer Notebook)
