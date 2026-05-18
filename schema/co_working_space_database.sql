-- ============================================================
-- Co-Working Space Booking System
-- Oracle SQL Schema — Full Database
-- ============================================================
-- Covers: Workspace, Rooms, Amenities, Users, Employees,
--         Shifts, Individual & Group Bookings, Payments,
--         Lost & Found, Product Store
-- Target: Oracle 19c+
-- ============================================================


-- ============================================================
-- SECTION 1: CREATE TABLES
-- ============================================================


-- ------------------------------------------------------------
-- 1.1  WORKSPACE
--      Top-level operational unit. Stores all system-wide
--      configurable parameters (grace period, deposit rate, etc.)
-- ------------------------------------------------------------
CREATE TABLE WORKSPACE (
    WorkspaceID                 NUMBER(5)       PRIMARY KEY,
    WorkspaceName               VARCHAR2(100)   NOT NULL,
    GracePeriodMinutes          NUMBER(3)       DEFAULT 30  NOT NULL,
    CancellationThresholdHours  NUMBER(2)       DEFAULT 2   NOT NULL,
    DepositRatePercent          NUMBER(3)       DEFAULT 25  NOT NULL,
    TaxRatePercent              NUMBER(5,2)     DEFAULT 14.00 NOT NULL,
    DepositPaymentWindowMinutes NUMBER(3)       DEFAULT 15  NOT NULL
);


-- ------------------------------------------------------------
-- 1.2  ROOM
--      Physical room within a workspace.
--      PrimaryType discriminates Individual vs Group (BR-01-001).
--      BaseHourlyPrice and Capacity are snapshotted at booking
--      creation and must not be retroactively changed (SYS-02).
-- ------------------------------------------------------------
CREATE TABLE ROOM (
    RoomID          NUMBER(5)       PRIMARY KEY,
    WorkspaceID     NUMBER(5)       NOT NULL,
    RoomName        VARCHAR2(100)   NOT NULL,
    PrimaryType     VARCHAR2(10)    NOT NULL,   -- 'Individual' | 'Group'
    BaseHourlyPrice NUMBER(10,2)    NOT NULL,
    Capacity        NUMBER(3)       NOT NULL,
    IsActive        CHAR(1)         DEFAULT 'Y',

    CONSTRAINT CHK_Room_PrimaryType CHECK (PrimaryType IN ('Individual', 'Group')),
    CONSTRAINT CHK_Room_Capacity    CHECK (Capacity > 0),
    CONSTRAINT CHK_Room_Price       CHECK (BaseHourlyPrice >= 0),
    CONSTRAINT CHK_Room_IsActive    CHECK (IsActive IN ('Y', 'N')),
    CONSTRAINT FK_Room_Workspace    FOREIGN KEY (WorkspaceID) REFERENCES WORKSPACE(WorkspaceID)
);


-- ------------------------------------------------------------
-- 1.3  AMENITY
--      Feature or equipment item (e.g. Wi-Fi, Projector, PS5).
-- ------------------------------------------------------------
CREATE TABLE AMENITY (
    AmenityID   NUMBER(5)       PRIMARY KEY,
    AmenityName VARCHAR2(100)   NOT NULL,
    Description VARCHAR2(500)
);


-- ------------------------------------------------------------
-- 1.4  ROOM_AMENITY  (Junction — resolves ROOM ↔ AMENITY M:M)
--      Each room must have at least one amenity (BR-01-002).
-- ------------------------------------------------------------
CREATE TABLE ROOM_AMENITY (
    RoomID    NUMBER(5) NOT NULL,
    AmenityID NUMBER(5) NOT NULL,

    CONSTRAINT PK_RoomAmenity PRIMARY KEY (RoomID, AmenityID),
    CONSTRAINT FK_RA_Room     FOREIGN KEY (RoomID)    REFERENCES ROOM(RoomID),
    CONSTRAINT FK_RA_Amenity  FOREIGN KEY (AmenityID) REFERENCES AMENITY(AmenityID)
);


-- ------------------------------------------------------------
-- 1.5  CUSTOMER_USER
--      Customer who makes individual or group bookings.
--      Business key: (FullName + PhoneNumber) — must be unique
--      and is used for overlap prevention (BR-04-004).
-- ------------------------------------------------------------
CREATE TABLE CUSTOMER_USER (
    UserID      NUMBER(5)       PRIMARY KEY,
    FullName    VARCHAR2(100)   NOT NULL,
    PhoneNumber VARCHAR2(20)    NOT NULL,
    Email       VARCHAR2(100),

    CONSTRAINT UK_User_NamePhone UNIQUE (FullName, PhoneNumber)
);


-- ------------------------------------------------------------
-- 1.6  EMPLOYEE
--      Staff member who processes bookings, check-ins,
--      check-outs, and lost & found entries.
-- ------------------------------------------------------------
CREATE TABLE EMPLOYEE (
    EmployeeID  NUMBER(5)       PRIMARY KEY,
    FullName    VARCHAR2(100)   NOT NULL,
    PhoneNumber VARCHAR2(20)    NOT NULL,
    Email       VARCHAR2(100),
    Role        VARCHAR2(50),
    IsActive    CHAR(1)         DEFAULT 'Y',

    CONSTRAINT CHK_Emp_IsActive CHECK (IsActive IN ('Y', 'N'))
);


-- ------------------------------------------------------------
-- 1.7  SHIFT
--      Defined time window during which an employee covers
--      workspace operations.
--      Shifts for the same employee on the same day must not
--      overlap (BR-07-001).
-- ------------------------------------------------------------
CREATE TABLE SHIFT (
    ShiftID     NUMBER(5)   PRIMARY KEY,
    EmployeeID  NUMBER(5)   NOT NULL,
    ShiftDate   DATE        NOT NULL,
    StartTime   DATE        NOT NULL,
    EndTime     DATE        NOT NULL,

    CONSTRAINT FK_Shift_Employee FOREIGN KEY (EmployeeID) REFERENCES EMPLOYEE(EmployeeID),
    CONSTRAINT CHK_ShiftTime     CHECK (EndTime > StartTime)
);


-- ------------------------------------------------------------
-- 1.8  INDIVIDUAL_BOOKING
--      Single-seat reservation for an individual room.
--      No end time at creation — duration computed at checkout.
--      Three employee FKs track creation, check-in, check-out
--      staff separately (BR-07-003).
--
--      Status lifecycle:
--        Pending → Checked-In → Checked-Out
--                             → Auto-Cancelled
--                             → Cancelled
--
--      Walk-in bookings skip Pending and begin at
--      Checked-In directly (BR-04-002).
-- ------------------------------------------------------------
CREATE TABLE INDIVIDUAL_BOOKING (
    BookingID         NUMBER(10)      PRIMARY KEY,
    UserID            NUMBER(5)       NOT NULL,
    RoomID            NUMBER(5)       NOT NULL,
    ShiftID_Creation  NUMBER(5)       NOT NULL,
    ShiftID_CheckIn   NUMBER(5),
    ShiftID_CheckOut  NUMBER(5),
    EmpID_Creation    NUMBER(5)       NOT NULL,
    EmpID_CheckIn     NUMBER(5),
    EmpID_CheckOut    NUMBER(5),
    Channel           VARCHAR2(10)    NOT NULL,
    Status            VARCHAR2(20)    DEFAULT 'Pending',
    PriceSnapshot     NUMBER(10,2)    NOT NULL,   -- Locked from ROOM.BaseHourlyPrice at creation
    CreatedAt         DATE            DEFAULT SYSDATE NOT NULL,
    GracePeriodExpiry DATE,
    CheckInTime       DATE,
    CheckOutTime      DATE,
    TotalAmount       NUMBER(10,2),

    CONSTRAINT CHK_IB_Channel CHECK (Channel IN ('Online', 'Walk-In')),
    CONSTRAINT CHK_IB_Status  CHECK (Status  IN ('Pending', 'Checked-In', 'Checked-Out', 'Auto-Cancelled', 'Cancelled')),

    CONSTRAINT FK_IB_User         FOREIGN KEY (UserID)           REFERENCES CUSTOMER_USER(UserID),
    CONSTRAINT FK_IB_Room         FOREIGN KEY (RoomID)           REFERENCES ROOM(RoomID),
    CONSTRAINT FK_IB_ShiftCreate  FOREIGN KEY (ShiftID_Creation) REFERENCES SHIFT(ShiftID),
    CONSTRAINT FK_IB_ShiftCheckIn FOREIGN KEY (ShiftID_CheckIn)  REFERENCES SHIFT(ShiftID),
    CONSTRAINT FK_IB_ShiftCheckOut FOREIGN KEY (ShiftID_CheckOut) REFERENCES SHIFT(ShiftID),
    CONSTRAINT FK_IB_EmpCreate    FOREIGN KEY (EmpID_Creation)   REFERENCES EMPLOYEE(EmployeeID),
    CONSTRAINT FK_IB_EmpCheckIn   FOREIGN KEY (EmpID_CheckIn)    REFERENCES EMPLOYEE(EmployeeID),
    CONSTRAINT FK_IB_EmpCheckOut  FOREIGN KEY (EmpID_CheckOut)   REFERENCES EMPLOYEE(EmployeeID)
);


-- ------------------------------------------------------------
-- 1.9  GROUP_BOOKING
--      Full-room reservation with a scheduled time window
--      and mandatory upfront deposit.
--
--      Billing:
--        Deposit    = PriceSnapshot × BookedDuration × DepositRate (25%)
--        FinalBill  = (PriceSnapshot × BookedDuration) − Deposit + TaxAmount
--
--      Billing always uses BookedDuration, even on early departure
--      (BR-05-004). Room is blocked for the full window once Confirmed.
--
--      Status lifecycle:
--        Pending → Confirmed → Checked-In → Completed
--                                         → Cancelled-Refunded
--                                         → Cancelled-Forfeited
--                            → No-Show
-- ------------------------------------------------------------
CREATE TABLE GROUP_BOOKING (
    GroupBookingID                NUMBER(10)  PRIMARY KEY,
    RoomID                        NUMBER(5)   NOT NULL,
    ShiftID_Creation              NUMBER(5)   NOT NULL,
    ShiftID_CheckIn               NUMBER(5),
    EmpID_Creation                NUMBER(5)   NOT NULL,
    EmpID_CheckIn                 NUMBER(5),
    EmpID_CheckOut                NUMBER(5),
    Channel                       VARCHAR2(10)    NOT NULL,
    Status                        VARCHAR2(30)    DEFAULT 'Pending',
    PriceSnapshot                 NUMBER(10,2)    NOT NULL,
    ScheduledStart                DATE            NOT NULL,
    ScheduledEnd                  DATE            NOT NULL,
    DepositAmount                 NUMBER(10,2)    NOT NULL,
    DepositPaid                   CHAR(1)         DEFAULT 'N',
    DepositPaidAt                 DATE,
    CancellationThresholdSnapshot NUMBER(2)       NOT NULL,
    ActualCheckIn                 DATE,
    ActualCheckOut                DATE,
    TotalAmount                   NUMBER(10,2),
    TaxAmount                     NUMBER(10,2),
    CreatedAt                     DATE            DEFAULT SYSDATE NOT NULL,

    CONSTRAINT CHK_GB_Channel    CHECK (Channel IN ('Online', 'Walk-In')),
    CONSTRAINT CHK_GB_Status     CHECK (Status  IN ('Pending', 'Confirmed', 'Checked-In', 'Completed', 'Cancelled-Refunded', 'Cancelled-Forfeited', 'No-Show')),
    CONSTRAINT CHK_GB_Deposit    CHECK (DepositPaid IN ('Y', 'N')),
    CONSTRAINT CHK_GB_Times      CHECK (ScheduledEnd > ScheduledStart),

    CONSTRAINT FK_GB_Room         FOREIGN KEY (RoomID)           REFERENCES ROOM(RoomID),
    CONSTRAINT FK_GB_ShiftCreate  FOREIGN KEY (ShiftID_Creation) REFERENCES SHIFT(ShiftID),
    CONSTRAINT FK_GB_ShiftCheckIn FOREIGN KEY (ShiftID_CheckIn)  REFERENCES SHIFT(ShiftID),
    CONSTRAINT FK_GB_EmpCreate    FOREIGN KEY (EmpID_Creation)   REFERENCES EMPLOYEE(EmployeeID),
    CONSTRAINT FK_GB_EmpCheckIn   FOREIGN KEY (EmpID_CheckIn)    REFERENCES EMPLOYEE(EmployeeID),
    CONSTRAINT FK_GB_EmpCheckOut  FOREIGN KEY (EmpID_CheckOut)   REFERENCES EMPLOYEE(EmployeeID)
);


-- ------------------------------------------------------------
-- 1.10 PAYMENT
--      Financial transaction linked to either an individual
--      or group booking.
--      Individual: full payment at checkout (PaymentType = 'Full').
--      Group:      deposit at creation, balance at checkout.
--      Refund fields track deposit refunds on valid cancellations.
-- ------------------------------------------------------------
CREATE TABLE PAYMENT (
    PaymentID        NUMBER(10)  PRIMARY KEY,
    BookingID        NUMBER(10)  NOT NULL,
    BookingType      VARCHAR2(10)    NOT NULL,
    Amount           NUMBER(10,2)    NOT NULL,
    Method           VARCHAR2(15)    NOT NULL,
    PaymentType      VARCHAR2(10)    NOT NULL,
    PaidAt           DATE            DEFAULT SYSDATE NOT NULL,
    ProcessedByEmpID NUMBER(5)       NOT NULL,
    IsRefunded       CHAR(1)         DEFAULT 'N',
    RefundedAt       DATE,
    RefundReason     VARCHAR2(500),

    CONSTRAINT CHK_Pay_BookingType CHECK (BookingType IN ('Individual', 'Group')),
    CONSTRAINT CHK_Pay_Method      CHECK (Method      IN ('Cash', 'Credit Card', 'InstaPay')),
    CONSTRAINT CHK_Pay_Type        CHECK (PaymentType IN ('Deposit', 'Balance', 'Full')),
    CONSTRAINT CHK_Pay_IsRefunded  CHECK (IsRefunded  IN ('Y', 'N')),

    CONSTRAINT FK_Payment_Employee FOREIGN KEY (ProcessedByEmpID) REFERENCES EMPLOYEE(EmployeeID)
);


-- ------------------------------------------------------------
-- 1.11 LOST_FOUND
--      Logs items found on the premises.
--      Four fields are mandatory at entry (BR-08-001):
--        Description, RoomID, FoundAt, LoggedByEmpID.
--      AuthorizingEmpID required for Disposed status (BR-08-002).
--
--      Status lifecycle: Found → Stored → Claimed | Disposed
-- ------------------------------------------------------------
CREATE TABLE LOST_FOUND (
    ItemID           NUMBER(10)  PRIMARY KEY,
    Description      VARCHAR2(500)   NOT NULL,
    RoomID           NUMBER(5)       NOT NULL,
    FoundAt          DATE            DEFAULT SYSDATE NOT NULL,
    LoggedByEmpID    NUMBER(5)       NOT NULL,
    Status           VARCHAR2(10)    DEFAULT 'Found',
    ClaimedByName    VARCHAR2(100),
    ClaimedAt        DATE,
    DisposalReason   VARCHAR2(500),
    AuthorizingEmpID NUMBER(5),

    CONSTRAINT CHK_LF_Status  CHECK (Status IN ('Found', 'Stored', 'Claimed', 'Disposed')),

    CONSTRAINT FK_LF_Room      FOREIGN KEY (RoomID)          REFERENCES ROOM(RoomID),
    CONSTRAINT FK_LF_LoggedBy  FOREIGN KEY (LoggedByEmpID)   REFERENCES EMPLOYEE(EmployeeID),
    CONSTRAINT FK_LF_AuthBy    FOREIGN KEY (AuthorizingEmpID) REFERENCES EMPLOYEE(EmployeeID)
);


-- ------------------------------------------------------------
-- 1.12 PRODUCT
--      Item available for purchase via the workspace store.
--      A single shared catalogue serves both channels (BR-09-002).
--      StockQuantity = 0 or IsActive = 'N' blocks purchase
--      on both channels.
-- ------------------------------------------------------------
CREATE TABLE PRODUCT (
    ProductID     NUMBER(5)       PRIMARY KEY,
    ProductName   VARCHAR2(100)   NOT NULL,
    Description   VARCHAR2(500),
    Price         NUMBER(10,2)    NOT NULL,
    StockQuantity NUMBER(5)       DEFAULT 0 NOT NULL,
    IsActive      CHAR(1)         DEFAULT 'Y',

    CONSTRAINT CHK_Prod_IsActive CHECK (IsActive IN ('Y', 'N')),
    CONSTRAINT CHK_Prod_Price    CHECK (Price >= 0),
    CONSTRAINT CHK_Prod_Stock    CHECK (StockQuantity >= 0)
);


-- ------------------------------------------------------------
-- 1.13 STORE_ORDER
--      Customer purchase transaction from the workspace store.
--      UserID is nullable — guest/walk-in orders are allowed
--      (BR-09-003). Store transactions are independent from
--      booking payments (BR-09-001).
-- ------------------------------------------------------------
CREATE TABLE STORE_ORDER (
    OrderID          NUMBER(10)  PRIMARY KEY,
    Channel          VARCHAR2(10)    NOT NULL,
    OrderedAt        DATE            DEFAULT SYSDATE NOT NULL,
    TotalAmount      NUMBER(10,2)    NOT NULL,
    PaymentMethod    VARCHAR2(15)    NOT NULL,
    UserID           NUMBER(5),          -- Nullable: guest orders
    CustomerName     VARCHAR2(100),
    CustomerPhone    VARCHAR2(20),
    ProcessedByEmpID NUMBER(5),

    CONSTRAINT CHK_SO_Channel  CHECK (Channel       IN ('Online', 'On-Site')),
    CONSTRAINT CHK_SO_Payment  CHECK (PaymentMethod IN ('Cash', 'Credit Card', 'InstaPay')),

    CONSTRAINT FK_SO_User     FOREIGN KEY (UserID)           REFERENCES CUSTOMER_USER(UserID),
    CONSTRAINT FK_SO_Employee FOREIGN KEY (ProcessedByEmpID) REFERENCES EMPLOYEE(EmployeeID)
);


-- ------------------------------------------------------------
-- 1.14 ORDER_ITEM  (Junction / Line Item)
--      Resolves STORE_ORDER ↔ PRODUCT M:M.
--      UnitPriceSnapshot locks the product price at time
--      of purchase (SYS-02 equivalent for store).
-- ------------------------------------------------------------
CREATE TABLE ORDER_ITEM (
    OrderID          NUMBER(10)  NOT NULL,
    ProductID        NUMBER(5)   NOT NULL,
    Quantity         NUMBER(3)   NOT NULL,
    UnitPriceSnapshot NUMBER(10,2) NOT NULL,

    CONSTRAINT PK_OrderItem  PRIMARY KEY (OrderID, ProductID),
    CONSTRAINT CHK_OI_Qty    CHECK (Quantity > 0),
    CONSTRAINT FK_OI_Order   FOREIGN KEY (OrderID)   REFERENCES STORE_ORDER(OrderID),
    CONSTRAINT FK_OI_Product FOREIGN KEY (ProductID) REFERENCES PRODUCT(ProductID)
);


-- ============================================================
-- SECTION 2: SEQUENCES
--   Used for surrogate primary key generation across all tables.
-- ============================================================

CREATE SEQUENCE SEQ_WORKSPACE       START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_ROOM            START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_AMENITY         START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_USER            START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_EMPLOYEE        START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_SHIFT           START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_INDIV_BOOKING   START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE SEQ_GROUP_BOOKING   START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE SEQ_PAYMENT         START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE SEQ_LOST_FOUND      START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_PRODUCT         START WITH 1    INCREMENT BY 1;
CREATE SEQUENCE SEQ_STORE_ORDER     START WITH 5000 INCREMENT BY 1;


-- ============================================================
-- SECTION 3: SEED DATA (Sample INSERT statements)
-- ============================================================

-- ------------------------------------------------------------
-- Workspaces
-- ------------------------------------------------------------
INSERT INTO WORKSPACE (WorkspaceID, WorkspaceName, GracePeriodMinutes, CancellationThresholdHours, DepositRatePercent, TaxRatePercent, DepositPaymentWindowMinutes)
VALUES (SEQ_WORKSPACE.NEXTVAL, 'Alexandria Library Co-Working', 30, 2, 25, 14.00, 15);

INSERT INTO WORKSPACE (WorkspaceID, WorkspaceName, GracePeriodMinutes, CancellationThresholdHours, DepositRatePercent, TaxRatePercent, DepositPaymentWindowMinutes)
VALUES (SEQ_WORKSPACE.NEXTVAL, 'Cairo Tower Business Hub', 45, 4, 25, 14.00, 20);


-- ------------------------------------------------------------
-- Rooms
-- ------------------------------------------------------------
INSERT INTO ROOM (RoomID, WorkspaceID, RoomName, PrimaryType, BaseHourlyPrice, Capacity, IsActive)
VALUES (SEQ_ROOM.NEXTVAL, 1, 'Room A101 - Quiet', 'Individual', 50.00, 1, 'Y');

INSERT INTO ROOM (RoomID, WorkspaceID, RoomName, PrimaryType, BaseHourlyPrice, Capacity, IsActive)
VALUES (SEQ_ROOM.NEXTVAL, 1, 'Room B202 - Meeting', 'Group', 150.00, 6, 'Y');

INSERT INTO ROOM (RoomID, WorkspaceID, RoomName, PrimaryType, BaseHourlyPrice, Capacity, IsActive)
VALUES (SEQ_ROOM.NEXTVAL, 2, 'Office 10 - Private', 'Individual', 75.00, 1, 'Y');

INSERT INTO ROOM (RoomID, WorkspaceID, RoomName, PrimaryType, BaseHourlyPrice, Capacity, IsActive)
VALUES (SEQ_ROOM.NEXTVAL, 2, 'Hall C - Conference', 'Group', 300.00, 20, 'Y');


-- ------------------------------------------------------------
-- Employees
-- ------------------------------------------------------------
INSERT INTO EMPLOYEE (EmployeeID, FullName, PhoneNumber, Email, Role, IsActive)
VALUES (SEQ_EMPLOYEE.NEXTVAL, 'Ahmed Mohamed', '01001234567', 'ahmed@cowork.com', 'Operations Manager', 'Y');

INSERT INTO EMPLOYEE (EmployeeID, FullName, PhoneNumber, Email, Role, IsActive)
VALUES (SEQ_EMPLOYEE.NEXTVAL, 'Sara Khaled', '01007654321', 'sara@cowork.com', 'Receptionist', 'Y');


-- ------------------------------------------------------------
-- Shifts
-- ------------------------------------------------------------
INSERT INTO SHIFT (ShiftID, EmployeeID, ShiftDate, StartTime, EndTime)
VALUES (SEQ_SHIFT.NEXTVAL, 1,
        TO_DATE('2026-05-10', 'YYYY-MM-DD'),
        TO_DATE('2026-05-10 09:00:00', 'YYYY-MM-DD HH24:MI:SS'),
        TO_DATE('2026-05-10 17:00:00', 'YYYY-MM-DD HH24:MI:SS'));


-- ------------------------------------------------------------
-- Customers
-- ------------------------------------------------------------
INSERT INTO CUSTOMER_USER (UserID, FullName, PhoneNumber, Email)
VALUES (SEQ_USER.NEXTVAL, 'Mahmoud Ali', '01221122334', 'mahmoud@email.com');


-- ------------------------------------------------------------
-- Amenities
-- ------------------------------------------------------------
INSERT INTO AMENITY (AmenityID, AmenityName, Description)
VALUES (SEQ_AMENITY.NEXTVAL, 'Wi-Fi', 'High-speed fiber internet');

INSERT INTO AMENITY (AmenityID, AmenityName, Description)
VALUES (SEQ_AMENITY.NEXTVAL, 'Printer', 'Multifunction printer/scanner');

INSERT INTO AMENITY (AmenityID, AmenityName, Description)
VALUES (SEQ_AMENITY.NEXTVAL, 'PlayStation 5', 'Gaming console');


-- ------------------------------------------------------------
-- Room ↔ Amenity assignments
-- ------------------------------------------------------------
INSERT INTO ROOM_AMENITY (RoomID, AmenityID) VALUES (1, 1); -- A101: Wi-Fi
INSERT INTO ROOM_AMENITY (RoomID, AmenityID) VALUES (1, 2); -- A101: Printer
INSERT INTO ROOM_AMENITY (RoomID, AmenityID) VALUES (2, 1); -- B202: Wi-Fi
INSERT INTO ROOM_AMENITY (RoomID, AmenityID) VALUES (3, 1); -- Office 10: Wi-Fi
INSERT INTO ROOM_AMENITY (RoomID, AmenityID) VALUES (4, 1); -- Hall C: Wi-Fi
INSERT INTO ROOM_AMENITY (RoomID, AmenityID) VALUES (4, 3); -- Hall C: PlayStation 5


-- ------------------------------------------------------------
-- Sample individual booking (Online — Pending with grace window)
-- ------------------------------------------------------------
INSERT INTO INDIVIDUAL_BOOKING (
    BookingID, UserID, RoomID, ShiftID_Creation, EmpID_Creation,
    Channel, Status, PriceSnapshot, CreatedAt, GracePeriodExpiry
)
VALUES (
    SEQ_INDIV_BOOKING.NEXTVAL, 1, 1, 1, 1,
    'Online', 'Pending', 50.00, SYSDATE, SYSDATE + 30/1440
);


-- ------------------------------------------------------------
-- Sample group booking (Online — Pending, awaiting deposit)
-- ------------------------------------------------------------
INSERT INTO GROUP_BOOKING (
    GroupBookingID, RoomID, ShiftID_Creation, EmpID_Creation,
    Channel, Status, PriceSnapshot,
    ScheduledStart, ScheduledEnd,
    DepositAmount, CancellationThresholdSnapshot, CreatedAt
)
VALUES (
    SEQ_GROUP_BOOKING.NEXTVAL, 2, 1, 1,
    'Online', 'Pending', 150.00,
    TO_DATE('2026-05-15 14:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    TO_DATE('2026-05-15 16:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    75.00, 2, SYSDATE
);


-- ------------------------------------------------------------
-- Sample product and store order
-- ------------------------------------------------------------
INSERT INTO PRODUCT (ProductID, ProductName, Price, StockQuantity, IsActive)
VALUES (SEQ_PRODUCT.NEXTVAL, 'Arabic Coffee', 15.00, 50, 'Y');

INSERT INTO STORE_ORDER (OrderID, Channel, TotalAmount, PaymentMethod, UserID, ProcessedByEmpID)
VALUES (SEQ_STORE_ORDER.NEXTVAL, 'On-Site', 15.00, 'Cash', 1, 2);

INSERT INTO ORDER_ITEM (OrderID, ProductID, Quantity, UnitPriceSnapshot)
VALUES (SEQ_STORE_ORDER.CURRVAL, 1, 1, 15.00);

COMMIT;


-- ============================================================
-- SECTION 4: SAMPLE SELECT QUERIES
-- ============================================================

-- All rooms with type, price, and availability status
SELECT RoomID, RoomName, PrimaryType, BaseHourlyPrice, Capacity, IsActive
FROM ROOM
ORDER BY PrimaryType, RoomName;

-- Active individual rooms only
SELECT RoomName, BaseHourlyPrice
FROM ROOM
WHERE PrimaryType = 'Individual' AND IsActive = 'Y';

-- Active group rooms only
SELECT RoomName, Capacity, BaseHourlyPrice
FROM ROOM
WHERE PrimaryType = 'Group' AND IsActive = 'Y';

-- Each room with its comma-separated amenity list
SELECT
    R.RoomName,
    R.PrimaryType,
    LISTAGG(A.AmenityName, ', ') WITHIN GROUP (ORDER BY A.AmenityName) AS Amenities
FROM ROOM R
JOIN ROOM_AMENITY RA ON R.RoomID    = RA.RoomID
JOIN AMENITY      A  ON RA.AmenityID = A.AmenityID
GROUP BY R.RoomName, R.PrimaryType;

-- Active individual bookings (Pending or Checked-In)
SELECT
    IB.BookingID,
    CU.FullName,
    R.RoomName,
    IB.Status,
    IB.Channel,
    IB.CreatedAt,
    IB.GracePeriodExpiry
FROM INDIVIDUAL_BOOKING IB
JOIN CUSTOMER_USER CU ON IB.UserID = CU.UserID
JOIN ROOM          R  ON IB.RoomID = R.RoomID
WHERE IB.Status IN ('Pending', 'Checked-In');

-- All group bookings with room info
SELECT
    GB.GroupBookingID,
    R.RoomName,
    R.Capacity,
    GB.ScheduledStart,
    GB.ScheduledEnd,
    GB.Status,
    GB.DepositAmount,
    GB.DepositPaid
FROM GROUP_BOOKING GB
JOIN ROOM R ON GB.RoomID = R.RoomID
ORDER BY GB.ScheduledStart;

-- Payment summary per booking type
SELECT
    BookingType,
    PaymentType,
    Method,
    COUNT(*)         AS TxCount,
    SUM(Amount)      AS TotalAmount
FROM PAYMENT
GROUP BY BookingType, PaymentType, Method
ORDER BY BookingType, PaymentType;

-- Open lost & found items (not yet Claimed or Disposed)
SELECT
    LF.ItemID,
    LF.Description,
    R.RoomName,
    LF.FoundAt,
    LF.Status,
    E.FullName AS LoggedBy
FROM LOST_FOUND LF
JOIN ROOM     R ON LF.RoomID       = R.RoomID
JOIN EMPLOYEE E ON LF.LoggedByEmpID = E.EmployeeID
WHERE LF.Status IN ('Found', 'Stored')
ORDER BY LF.FoundAt DESC;
