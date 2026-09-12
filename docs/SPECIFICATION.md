## Enterprise Bike Showroom Management System

You are a senior Flutter architect, backend architect, PostgreSQL/Supabase expert, UI/UX designer, security engineer, and enterprise application developer.

I want you to design and build a **production-ready, enterprise-level Bike Showroom Management System** using Flutter.

The application must target:

```text
Android
iOS
Web
Windows
```

The system must be scalable, secure, responsive, modular, maintainable, offline-capable, and suitable for real-world multi-showroom business operations.

Do not provide a prototype-only architecture.

Build the project using production-grade patterns and reusable components.

---

# 1. Technology Stack

Mandatory technologies:

```text
Flutter
Dart
GetX
Dio
Supabase
PostgreSQL
Firebase Cloud Messaging
SharedPreferences
Hive or SQLite
```

Use:

```text
GetX
    → State management
    → Dependency injection
    → Routing
    → Reactive state

Dio
    → REST/API communication
    → Interceptors
    → Authentication headers
    → Error handling
    → Retry handling

Supabase
    → PostgreSQL database
    → Authentication
    → Storage
    → Row Level Security
    → RPC/database functions
    → Realtime where required

Firebase Cloud Messaging
    → Push notifications

SharedPreferences
    → Lightweight local settings
    → Session-related local flags

Hive or SQLite
    → Offline cache
    → Draft transactions
    → Sync queue
    → Local persistence
```

Prefer a clean abstraction so the local database implementation can be changed later without affecting feature code.

---

# 2. Global Coding Standards

Follow these rules throughout the complete project.

## Architecture

Use:

```text
Feature-based architecture
Repository pattern
Service layer
GetX controllers
GetX bindings
Dependency injection
Reusable common widgets
Reusable common models
Centralized constants
Centralized error handling
Centralized API handling
Centralized validation
```

## Public APIs

All classes, functions, methods, controllers, repositories, services, helpers, extensions, and reusable members must be **PUBLIC**.

Do not use private `_` members for project classes/functions/methods unless Dart requires it internally.

For example:

```dart
class CustomerController extends GetxController {
  RxList<CustomerModel> customers = <CustomerModel>[].obs;

  Future<void> loadCustomers() async {
    // ...
  }
}
```

Avoid:

```dart
class CustomerController {
  final RxList<CustomerModel> _customers = <CustomerModel>[].obs;
}
```

---

# 3. Project Architecture

Use this structure:

```text
lib/
├── config/
│   ├── app_config.dart
│   ├── environment_config.dart
│   ├── theme_config.dart
│   ├── route_config.dart
│   └── supabase_config.dart
│
├── core/
│   ├── constants/
│   ├── enums/
│   ├── extensions/
│   ├── helpers/
│   ├── validators/
│   ├── errors/
│   ├── utils/
│   └── network/
│
├── common/
│   ├── widgets/
│   ├── controllers/
│   ├── models/
│   ├── services/
│   └── layouts/
│
├── features/
│   ├── auth/
│   │   ├── models/
│   │   ├── controllers/
│   │   ├── repositories/
│   │   ├── services/
│   │   ├── bindings/
│   │   └── views/
│   │
│   ├── dashboard/
│   ├── showroom/
│   ├── users/
│   ├── roles/
│   ├── products/
│   ├── inventory/
│   ├── customers/
│   ├── sales/
│   ├── billing/
│   ├── payments/
│   ├── finance/
│   ├── emi/
│   ├── purchases/
│   ├── expenses/
│   ├── accounting/
│   ├── service/
│   ├── warranty/
│   ├── insurance/
│   ├── reminders/
│   ├── notifications/
│   ├── reports/
│   ├── documents/
│   ├── audit/
│   └── settings/
│
├── services/
│   ├── api_service.dart
│   ├── auth_service.dart
│   ├── storage_service.dart
│   ├── notification_service.dart
│   ├── local_database_service.dart
│   ├── sync_service.dart
│   ├── connectivity_service.dart
│   └── image_service.dart
│
├── routes/
│   ├── app_routes.dart
│   └── app_pages.dart
│
└── main.dart
```

Each feature must contain, where required:

```text
models
controllers
repositories
services
bindings
views
widgets
```

Do not put feature-specific business logic into generic/common folders.

---

# 4. Application Requirements

The application must support complete showroom operations:

```text
Authentication
Dashboard
Showroom Management
User Management
Role Management
Permission Management
Product/Bike Management
Inventory
Customers
Customer Vehicles
Sales
Billing
Invoices
Payments
Finance
EMI
Purchases
Suppliers
Expenses
Accounting
Free Servicing
Paid Servicing
Warranty
Insurance
Reminders
Notifications
Reports
Documents
Audit Logs
Settings
Offline Mode
Synchronization
```

---

# 5. Authentication

Use Supabase Auth.

Support:

```text
Email/password login
Password reset
Session persistence
Logout
Session expiration handling
Refresh token handling
```

Optional architecture support for:

```text
Phone authentication
OTP
Magic link
Social login
```

User session must be securely managed.

After authentication:

```text
Supabase Auth
      ↓
users
      ↓
user_roles
      ↓
roles
      ↓
permissions
      ↓
showroom access
      ↓
application
```

The application must not trust the Flutter client alone for authorization.

---

# 6. RBAC

Roles must include at least:

```text
SUPER ADMIN
ADMIN
SHOWROOM MANAGER
ACCOUNT MANAGER
SALES MANAGER
SALES STAFF
SERVICE MANAGER
SERVICE ADVISOR
TECHNICIAN
INVENTORY MANAGER
PURCHASE MANAGER
ACCOUNTANT
VIEWER
```

Permissions should use:

```text
module.action
```

Examples:

```text
dashboard.view

customers.view
customers.create
customers.edit
customers.delete
customers.export

products.view
products.create
products.edit
products.delete

inventory.view
inventory.create
inventory.transfer
inventory.adjust
inventory.delete

sales.view
sales.create
sales.edit
sales.cancel
sales.discount
sales.approve

billing.view
billing.create
billing.edit
billing.cancel
billing.print
billing.export

payments.view
payments.create
payments.edit
payments.cancel

emi.view
emi.create
emi.edit
emi.payment

service.view
service.create
service.edit
service.complete
service.bill
service.discount

reports.view
reports.export

users.view
users.create
users.edit
users.delete

roles.view
roles.manage

showroom.view
showroom.create
showroom.edit
```

Implement permission checks in:

```text
Flutter
GetX controllers
Navigation
Supabase RLS
Database functions
```

---

# 7. Multi-Showroom Architecture

The system must support multiple showrooms.

Every showroom-specific record must contain:

```text
showroom_id
```

Example:

```text
users
customers
inventory
sales
invoices
payments
purchases
expenses
services
loans
reminders
notifications
accounting
audit_logs
```

A user must only access the showrooms allowed by their role/assignment.

SUPER ADMIN can access all showrooms.

Normal users must never access another showroom's data.

Use Supabase PostgreSQL RLS.

---

# 8. Dashboard

Create responsive dashboards for different roles.

Dashboard widgets:

```text
Today's Sales
Monthly Sales
Today's Collection
Outstanding Amount
Total Customers
Active Loans
Upcoming EMI
Overdue EMI
Available Stock
Low Stock
Upcoming Services
Overdue Services
Insurance Expiry
Warranty Expiry
Monthly Expenses
Monthly Profit
Purchase Summary
Service Revenue
```

Charts:

```text
Sales Trend
Revenue Trend
Expense Trend
Profit Trend
Stock Distribution
Payment Method Distribution
Service Revenue
EMI Collection
```

Dashboard data should preferably come from optimized SQL views/functions.

---

# 9. Product / Bike Management

Allow users to create detailed bike/product records.

Fields should include:

```text
Brand
Model
Variant
Category
Engine CC
Fuel Type
Transmission
Mileage
Description
Base Price
Selling Price
Tax Rate
Warranty
Status
```

Product colors:

```text
Color Name
Hex Code
```

Product images:

```text
Multiple Images
Primary Image
Thumbnail
Sorting
Watermark Flag
```

Image architecture must support:

```text
Compression
Thumbnail generation
Caching
Lazy loading
Upload progress
Retry
Storage path management
```

Support showroom-specific image restrictions such as:

```text
watermark enabled
download restricted
preview only
```

---

# 10. Inventory

Inventory must track individual bikes.

Important fields:

```text
Stock Code
Product
Color
Chassis Number
Engine Number
Manufacturing Date
Model Year
Purchase Date
Purchase Price
Location
Status
```

Statuses:

```text
AVAILABLE
RESERVED
SOLD
DEMO
DAMAGED
IN_TRANSIT
RETURNED
```

Chassis number and engine number must be unique.

Support:

```text
Stock In
Stock Out
Stock Transfer
Stock Adjustment
Stock Reservation
Stock Release
Vehicle Sale Allocation
```

Stock transfer:

```text
From Showroom
To Showroom
Inventory
Transfer Date
Status
Notes
```

---

# 11. Customer Management

Customer module must support:

```text
Customer Code
Name
Phone
Alternate Phone
Email
Address
City
State
Pincode
Customer Type
Notes
Status
```

A customer may own multiple vehicles.

Customer profile should show:

```text
Customer Details
Vehicles
Sales
Invoices
Payments
EMIs
Services
Warranty
Insurance
Reminders
Documents
Outstanding
Transaction History
```

---

# 12. Customer Vehicle

A customer vehicle must contain:

```text
Customer
Product
Inventory
Registration Number
Registration Date
Chassis Number
Engine Number
Purchase Date
Delivery Date
Current Odometer
Warranty Start
Warranty End
Insurance Start
Insurance End
Next Service Date
Next Service KM
Status
```

One customer:

```text
Many vehicles
```

One inventory bike:

```text
Zero or one customer vehicle after sale
```

---

# 13. Sales

Sales must support complete bike sales.

Sale fields:

```text
Sale Number
Showroom
Customer
Vehicle
Salesperson
Sale Date
Subtotal
Discount
Tax
Other Charges
Total
Paid
Outstanding
Sale Type
Status
Notes
```

Sale items:

```text
Product
Inventory
Quantity
Unit Price
Discount
Tax
Total
```

Sale workflow:

```text
Customer Selection
      ↓
Vehicle/Product Selection
      ↓
Inventory Validation
      ↓
Price
      ↓
Discount
      ↓
Tax
      ↓
Other Charges
      ↓
Final Amount
      ↓
Payment
      ↓
Finance/EMI
      ↓
Invoice
      ↓
Customer Vehicle
      ↓
Warranty
      ↓
Free Service Schedule
      ↓
Accounting
```

Sale transaction must be atomic.

Prefer a Supabase RPC/database transaction instead of making independent client-side requests for each step.

---

# 14. Billing

Billing must support:

```text
Sale Invoice
Service Invoice
Accessory Invoice
Other Invoice
```

Invoice fields:

```text
Invoice Number
Customer
Showroom
Invoice Date
Invoice Type
Subtotal
Discount
Tax
Total
Paid
Outstanding
Status
PDF URL
```

Invoice items:

```text
Description
Product
Quantity
Unit Price
Discount
Tax Rate
Tax Amount
Total
```

Support:

```text
Generate PDF
Preview PDF
Print
Share
Download
Email
```

Invoices must be immutable after finalization except through controlled cancellation/reversal.

---

# 15. Payments

Payments must support:

```text
Cash
UPI
Card
Bank Transfer
Cheque
Finance
Online
Mixed
```

Payment record:

```text
Payment Number
Customer
Invoice
Sale
Service
EMI
Payment Date
Amount
Payment Method
Reference Number
Transaction ID
Status
Received By
Notes
```

Support:

```text
Partial Payment
Full Payment
Advance Payment
Refund
Payment Cancellation
Payment Reversal
```

Avoid physical deletion of financial transactions.

---

# 16. EMI / Finance

Finance companies:

```text
Company Name
Code
Contact Person
Phone
Email
Address
Status
```

Loan fields:

```text
Loan Number
Customer
Vehicle
Finance Company
Loan Amount
Down Payment
Interest Rate
Interest Type
Tenure
EMI Amount
Processing Fee
Start Date
End Date
Status
```

EMI schedule:

```text
EMI Number
Due Date
Principal
Interest
EMI Amount
Paid Amount
Remaining Amount
Paid Date
Status
```

Statuses:

```text
UPCOMING
DUE
PARTIAL
PAID
OVERDUE
CANCELLED
```

Provide a PostgreSQL function for EMI calculation.

Formula:

```text
EMI = P × r × (1+r)^n / ((1+r)^n - 1)
```

Where:

```text
P = Principal
r = Monthly interest rate
n = Number of months
```

Generate the entire EMI schedule on loan creation.

Support:

```text
Prepayment
Part Payment
Late Payment
Penalty
EMI Receipt
EMI Reminder
Overdue Tracking
```

---

# 17. Reminders

Reminder types:

```text
EMI
SERVICE
INSURANCE
WARRANTY
PAYMENT
DOCUMENT
CUSTOM
```

Reminder fields:

```text
Showroom
Customer
Vehicle
Reminder Type
Title
Message
Reminder Date
Reminder Time
Priority
Status
Reference ID
Reference Type
```

Reminder statuses:

```text
PENDING
SENT
COMPLETED
CANCELLED
```

Support automatic reminders:

```text
EMI before due date
EMI on due date
Overdue EMI
Service due
Service overdue
Insurance expiry
Warranty expiry
Outstanding payment
Document expiry
```

Use:

```text
Supabase scheduled functions / cron where appropriate
FCM
in-app notifications
```

---

# 18. Free Service

Create a configurable free-service plan.

Example:

```text
Free Service 1
Free Service 2
Free Service 3
Free Service 4
```

Each plan may contain:

```text
Service Number
Validity Days
Validity KM
Free Labour
Covered Items
```

For every sold vehicle generate its service schedule:

```text
Service 1 → Upcoming
Service 2 → Upcoming
Service 3 → Upcoming
```

When used:

```text
Upcoming → Used
```

The application must calculate free-service eligibility based on:

```text
Date
Odometer
Product
Service Plan
```

---

# 19. Paid Service

Paid service workflow:

```text
Booking
↓
Vehicle Reception
↓
Inspection
↓
Complaint Registration
↓
Job Card
↓
Technician Allocation
↓
Parts
↓
Labour
↓
Consumables
↓
Service Completion
↓
Invoice
↓
Payment
↓
Vehicle Delivery
```

Service types:

```text
FREE
PAID
WARRANTY
```

Statuses:

```text
BOOKED
RECEIVED
IN_PROGRESS
WAITING_FOR_PARTS
COMPLETED
DELIVERED
CANCELLED
```

Service items:

```text
PART
LABOUR
OIL
CONSUMABLE
ACCESSORY
OTHER
```

---

# 20. Warranty

Warranty must contain:

```text
Vehicle
Warranty Type
Start Date
End Date
Terms
Covered Components
Status
```

Warranty claims:

```text
Claim Number
Warranty
Service
Claim Date
Description
Claim Amount
Status
Resolution
```

The system should prevent invalid warranty claims after expiry unless authorized.

---

# 21. Insurance

Insurance fields:

```text
Vehicle
Insurance Company
Policy Number
Policy Type
Start Date
Expiry Date
Premium
Document
Status
```

Generate automatic insurance reminders.

Support:

```text
Expired
Expiring Soon
Active
Cancelled
```

---

# 22. Purchase Management

Supplier fields:

```text
Name
Phone
Email
Address
GST Number
Status
```

Purchase:

```text
Purchase Number
Supplier
Showroom
Purchase Date
Subtotal
Discount
Tax
Other Charges
Total
Paid
Outstanding
Status
```

Purchase items:

```text
Product
Inventory
Quantity
Unit Cost
Tax
Total
```

Purchase workflow should create/update inventory correctly.

---

# 23. Expense Management

Expense categories:

```text
Rent
Electricity
Salary
Transport
Marketing
Maintenance
Office
Fuel
Other
```

Expense:

```text
Expense Number
Category
Showroom
Expense Date
Amount
Payment Method
Description
Attachment
Status
Created By
Approved By
```

Support:

```text
Approval
Rejection
Attachment
Reports
Date filtering
Showroom filtering
```

---

# 24. Accounting

Implement proper double-entry accounting.

Accounts:

```text
ASSET
LIABILITY
EQUITY
INCOME
EXPENSE
```

Accounting transaction:

```text
Transaction Date
Reference Type
Reference ID
Description
Showroom
```

Accounting entry:

```text
Account
Debit
Credit
Description
```

Every transaction must satisfy:

```text
Total Debit = Total Credit
```

Example Sale:

```text
Customer Receivable / Cash      DR
Sales Revenue                  CR
Tax Payable                    CR
```

Example Expense:

```text
Expense Account                DR
Cash/Bank                      CR
```

Example Payment:

```text
Cash/Bank                      DR
Customer Receivable            CR
```

Accounting must be generated automatically from business transactions.

---

# 25. Reports

Create a complete reports module.

Reports:

```text
Sales Report
Purchase Report
Expense Report
Profit & Loss
Stock Report
Customer Outstanding
Payment Report
EMI Report
Overdue EMI
Service Report
Service Revenue
Free Service Report
Warranty Report
Insurance Expiry
Financial Summary
Showroom Summary
```

Every report should support:

```text
Date Range
Showroom Filter
Search
Status Filter
Export
Pagination
```

Exports:

```text
PDF
Excel/CSV
Print
```

---

# 26. Search / Filtering / Pagination

All large datasets must support:

```text
Server-side pagination
Debounced search
Sorting
Filtering
Date range
Status
Showroom
```

Do not load thousands of rows into Flutter unnecessarily.

Prefer:

```text
Supabase query
pagination
limit/offset or cursor-based pagination where appropriate
```

---

# 27. Offline Architecture

The application must continue working when the internet is unavailable.

Offline support should include:

```text
Cached Customers
Cached Products
Cached Inventory
Cached Sales Drafts
Cached Service Drafts
Cached Settings
Cached Reports where useful
```

Use a local database.

Create a sync queue:

```text
Pending Create
Pending Update
Pending Delete
Pending Payment
Pending Sale
Pending Service
```

Each sync operation should track:

```text
id
entity_type
entity_id
operation
payload
created_at
retry_count
last_error
status
```

Statuses:

```text
PENDING
SYNCING
SUCCESS
FAILED
```

When internet comes back:

```text
Connectivity Detected
      ↓
Sync Queue
      ↓
Server Validation
      ↓
Conflict Resolution
      ↓
Local Update
```

Never silently overwrite conflicting data.

---

# 28. Image Handling

Implement centralized image handling.

Support:

```text
Compression
Resize
Thumbnail
Caching
Upload progress
Retry
Placeholder
Error state
Lazy loading
```

Storage should use Supabase Storage.

Suggested buckets:

```text
product-images
customer-documents
vehicle-documents
invoice-documents
service-documents
insurance-documents
warranty-documents
expense-attachments
```

Important documents must not be publicly accessible by default.

Use secure access policies/signed URLs where appropriate.

---

# 29. Notifications

FCM integration must support:

```text
EMI reminders
Service reminders
Insurance expiry
Warranty expiry
Payment reminders
Approval notifications
Stock notifications
System notifications
```

Store notifications in database as well.

Notification fields:

```text
User
Customer
Showroom
Title
Message
Type
Reference
Read Status
Sent At
Created At
```

Implement:

```text
markRead()
markAllRead()
notificationBadgeCount
```

using GetX reactive state.

---

# 30. Local Preferences

SharedPreferences should store only lightweight data.

Examples:

```text
theme
language
selected_showroom
onboarding_complete
table_preferences
filter_preferences
```

Do not store sensitive credentials/passwords manually.

---

# 31. API Layer

Create centralized Dio service.

It should support:

```text
GET
POST
PUT
PATCH
DELETE
```

Features:

```text
Authentication interceptor
Authorization header
Logging interceptor
Error interceptor
Timeout
Retry
Connectivity detection
Request cancellation
Multipart upload
File download
```

Central error mapping:

```text
Network Error
Unauthorized
Forbidden
Validation Error
Not Found
Conflict
Server Error
Timeout
Unknown Error
```

The UI should never directly call Dio.

Use:

```text
Controller
   ↓
Repository
   ↓
Service/API
```

---

# 32. Repository Pattern

For every major feature:

```text
Controller
↓
Repository
↓
Data Source / Service
↓
Supabase / API / Local DB
```

Example:

```text
CustomerController
CustomerRepository
CustomerRemoteService
CustomerLocalService
CustomerModel
CustomerView
```

Repositories must abstract whether data comes from:

```text
remote
local
cache
sync
```

---

# 33. GetX Controllers

All controllers must use reactive state.

Example pattern:

```dart
RxList<CustomerModel> customers = <CustomerModel>[].obs;
RxBool isLoading = false.obs;
RxString errorMessage = ''.obs;
Rx<CustomerModel?> selectedCustomer = Rx<CustomerModel?>(null);
```

Use:

```text
Obx
GetBuilder
Workers
Bindings
Dependency Injection
```

Do not put large UI/business logic directly inside widgets.

---

# 34. GetX Bindings

Every feature must have its own binding.

Example:

```text
CustomerBinding
SalesBinding
InventoryBinding
ServiceBinding
BillingBinding
FinanceBinding
ReportsBinding
```

Bindings must register:

```text
Controller
Repository
Service
```

using GetX dependency injection.

---

# 35. Routing

Use centralized GetX routing.

Example:

```text
/login
/dashboard
/showrooms
/users
/products
/inventory
/customers
/sales
/billing
/payments
/finance
/emi
/purchases
/expenses
/accounting
/service
/warranty
/insurance
/reminders
/reports
/settings
```

Route guards must check:

```text
Authentication
Session
Role
Permission
Showroom Access
```

Unauthorized users must not be able to open protected routes.

---

# 36. UI / UX

Design should be modern and enterprise-oriented.

Requirements:

```text
Responsive
Clean
Professional
Fast
Accessible
Consistent
```

Support:

```text
Mobile
Tablet
Desktop
Web
Windows
```

Use responsive layouts instead of hardcoded dimensions.

Support:

```text
Light Theme
Dark Theme
Custom Accent Colors
```

Create centralized:

```text
AppColors
AppTypography
AppSpacing
AppRadius
AppShadows
AppTheme
```

Avoid hardcoding colors throughout widgets.

---

# 37. Navigation

Desktop:

```text
Sidebar
Top Bar
Breadcrumbs
Quick Actions
```

Mobile:

```text
Bottom Navigation
Drawer
App Bar
Floating Actions where useful
```

Navigation must be permission-aware.

---

# 38. Reusable Components

Build common widgets:

```text
AppButton
AppTextField
AppDropdown
AppDatePicker
AppSearchField
AppTable
AppDataGrid
AppCard
AppDialog
AppBottomSheet
AppLoader
AppEmptyState
AppErrorState
AppPagination
AppSnackbar
AppImage
AppAvatar
AppStatCard
AppChart
AppFilterBar
AppPermissionView
AppResponsiveLayout
```

These should be reusable throughout the application.

---

# 39. Validation

Centralize validation.

Validate:

```text
Required fields
Phone
Email
GST
PAN
Pincode
Amounts
Dates
Chassis
Engine Number
Registration Number
EMI
Tax
Discount
```

Validation should exist in both:

```text
Flutter
Database
```

Never depend only on UI validation.

---

# 40. Security

Implement:

```text
Supabase Auth
RLS
Role/permission validation
Showroom isolation
Secure Storage where necessary
Signed document URLs
Audit Logs
Input validation
SQL constraints
Foreign keys
Unique constraints
Rate limiting where applicable
```

Never expose:

```text
service-role keys
private secrets
database passwords
admin credentials
```

inside Flutter.

---

# 41. Audit Logging

Track:

```text
CREATE
UPDATE
DELETE
CANCEL
APPROVE
REJECT
PAYMENT
LOGIN
LOGOUT
STOCK_TRANSFER
STOCK_ADJUSTMENT
```

Audit log must contain:

```text
User
Showroom
Module
Action
Table
Record
Old Data
New Data
IP
User Agent
Timestamp
```

Financial records should not simply disappear from the system.

---

# 42. Soft Delete

Important business entities should support soft deletion where appropriate:

```text
is_deleted
deleted_at
deleted_by
```

Do not physically delete:

```text
Financial Transactions
Payments
Accounting Entries
Completed Sales
Finalized Invoices
Completed Service Records
EMI History
Audit Logs
```

Use:

```text
CANCELLED
REVERSED
REFUNDED
INACTIVE
```

where appropriate.

---

# 43. Database Design

Use:

```text
PostgreSQL
Supabase
UUID primary keys
Foreign keys
Indexes
Unique constraints
Check constraints
Triggers
Functions
Views
RLS policies
```

Core entities:

```text
showrooms
users
roles
permissions
user_roles
role_permissions
brands
products
product_colors
product_images
inventory
stock_transfers
customers
customer_vehicles
sales
sale_items
invoices
invoice_items
payments
finance_companies
loans
emi_schedules
suppliers
purchases
purchase_items
expense_categories
expenses
service_records
service_items
free_service_plans
vehicle_free_services
warranties
warranty_claims
insurance_policies
reminders
notifications
accounts
accounting_transactions
accounting_entries
attachments
audit_logs
```

---

# 44. Database Schema & Relationships

The application must use a properly normalized PostgreSQL database through Supabase.

The database must be designed for:

```text
Multi-showroom isolation
Role-based access
Customer lifecycle
Multiple vehicles per customer
Inventory tracking
Sales
Billing
Payments
EMI
Purchases
Expenses
Accounting
Free servicing
Paid servicing
Warranty
Insurance
Reminders
Notifications
Reporting
Audit logging
Offline synchronization
```

Use UUIDs as primary keys.

Common fields where applicable:

```text
id
showroom_id
created_at
updated_at
created_by
updated_by
```

---

# 45. Core Relationships

```text
SHOWROOM
│
├── USERS
├── CUSTOMERS
├── PRODUCTS
├── INVENTORY
├── SALES
├── PURCHASES
├── INVOICES
├── PAYMENTS
├── EXPENSES
├── SERVICES
├── LOANS
├── REMINDERS
├── NOTIFICATIONS
├── ACCOUNTING
└── AUDIT LOGS
```

Customer lifecycle:

```text
Customer
   ↓
Customer Vehicle
   ↓
Sale
   ↓
Invoice
   ↓
Payment
   ↓
Loan
   ↓
EMI
   ↓
Service
   ↓
Warranty
   ↓
Insurance
   ↓
Reminders
```

---

# 46. Database Tables

Implement at minimum the following structures.

## showrooms

```text
id UUID PK
name
code UNIQUE
address
city
state
pincode
phone
email
gst_number
pan_number
invoice_prefix
logo_url
status
settings JSONB
created_at
updated_at
```

## users

```text
id UUID PK
auth_user_id UUID UNIQUE
showroom_id UUID FK
name
email
phone
status
avatar_url
last_login_at
created_at
updated_at
```

## roles

```text
id UUID PK
name UNIQUE
description
is_system_role
created_at
updated_at
```

## permissions

```text
id UUID PK
module
action
description
created_at
```

## user_roles

```text
id UUID PK
user_id FK
role_id FK
created_at
```

## role_permissions

```text
id UUID PK
role_id FK
permission_id FK
created_at
```

## brands

```text
id UUID PK
name
status
created_at
updated_at
```

## products

```text
id UUID PK
brand_id FK
name
model
variant
category
engine_cc
fuel_type
transmission
mileage
description
base_price
selling_price
tax_rate
warranty_months
status
created_at
updated_at
```

## product_colors

```text
id UUID PK
product_id FK
color_name
hex_code
created_at
```

## product_images

```text
id UUID PK
product_id FK
image_url
thumbnail_url
is_primary
sort_order
watermark_enabled
created_at
```

## inventory

```text
id UUID PK
showroom_id FK
product_id FK
color_id FK
stock_code
chassis_number UNIQUE
engine_number UNIQUE
manufacturing_date
model_year
purchase_date
purchase_price
status
location
created_at
updated_at
```

## customers

```text
id UUID PK
showroom_id FK
customer_code
name
phone
alternate_phone
email
address
city
state
pincode
customer_type
notes
status
created_at
updated_at
```

## customer_vehicles

```text
id UUID PK
customer_id FK
inventory_id FK
product_id FK
registration_number
registration_date
chassis_number
engine_number
purchase_date
delivery_date
current_odometer
warranty_start
warranty_end
insurance_start
insurance_end
next_service_date
next_service_km
status
created_at
updated_at
```

## sales

```text
id UUID PK
showroom_id FK
customer_id FK
vehicle_id FK
salesperson_id FK
sale_number
sale_date
subtotal
discount
tax_amount
other_charges
total_amount
paid_amount
outstanding_amount
sale_type
status
notes
created_by
created_at
updated_at
```

## sale_items

```text
id UUID PK
sale_id FK
product_id FK
inventory_id FK
description
quantity
unit_price
discount
tax_amount
total_amount
```

## invoices

```text
id UUID PK
showroom_id FK
customer_id FK
sale_id FK NULL
service_id FK NULL
invoice_number
invoice_type
invoice_date
subtotal
discount
tax_amount
total_amount
paid_amount
outstanding_amount
status
pdf_url
created_by
created_at
updated_at
```

## invoice_items

```text
id UUID PK
invoice_id FK
product_id FK NULL
description
quantity
unit_price
discount
tax_rate
tax_amount
total_amount
```

## payments

```text
id UUID PK
showroom_id FK
customer_id FK
invoice_id FK NULL
sale_id FK NULL
service_id FK NULL
emi_id FK NULL
payment_number
payment_date
amount
payment_method
reference_number
transaction_id
status
notes
received_by
created_at
updated_at
```

## finance_companies

```text
id UUID PK
name
code
contact_person
phone
email
address
status
created_at
updated_at
```

## loans

```text
id UUID PK
showroom_id FK
customer_id FK
vehicle_id FK
finance_company_id FK
loan_number
loan_amount
down_payment
interest_rate
interest_type
tenure_months
emi_amount
processing_fee
start_date
end_date
status
created_at
updated_at
```

## emi_schedules

```text
id UUID PK
loan_id FK
emi_number
due_date
principal_amount
interest_amount
emi_amount
paid_amount
remaining_amount
paid_date
status
created_at
updated_at
```

## suppliers

```text
id UUID PK
name
phone
email
address
gst_number
status
created_at
updated_at
```

## purchases

```text
id UUID PK
showroom_id FK
supplier_id FK
purchase_number
purchase_date
subtotal
discount
tax_amount
other_charges
total_amount
paid_amount
outstanding_amount
status
created_by
created_at
updated_at
```

## purchase_items

```text
id UUID PK
purchase_id FK
product_id FK
inventory_id FK
quantity
unit_cost
tax_amount
total_amount
```

## expense_categories

```text
id UUID PK
name
description
created_at
```

## expenses

```text
id UUID PK
showroom_id FK
category_id FK
expense_number
expense_date
amount
payment_method
description
attachment_url
status
created_by
approved_by
created_at
updated_at
```

## service_records

```text
id UUID PK
showroom_id FK
customer_id FK
vehicle_id FK
service_number
booking_date
service_date
odometer_reading
service_type
service_status
service_advisor_id
technician_id
complaint
inspection_notes
work_done
next_service_date
next_service_km
subtotal
discount
tax_amount
total_amount
paid_amount
outstanding_amount
created_at
updated_at
```

## service_items

```text
id UUID PK
service_id FK
item_type
product_id FK NULL
description
quantity
unit_price
discount
tax_amount
total_amount
```

## free_service_plans

```text
id UUID PK
product_id FK
service_number
validity_days
validity_km
free_labour
covered_items JSONB
created_at
updated_at
```

## vehicle_free_services

```text
id UUID PK
vehicle_id FK
free_service_plan_id FK
service_id FK NULL
due_date
due_km
used_date
status
created_at
```

## warranties

```text
id UUID PK
vehicle_id FK
warranty_type
start_date
end_date
terms
covered_components JSONB
status
created_at
updated_at
```

## warranty_claims

```text
id UUID PK
warranty_id FK
service_id FK
claim_number
claim_date
description
claim_amount
status
resolution
created_at
updated_at
```

## insurance_policies

```text
id UUID PK
vehicle_id FK
insurance_company
policy_number
policy_type
start_date
expiry_date
premium
document_url
status
created_at
updated_at
```

## reminders

```text
id UUID PK
showroom_id FK
customer_id FK
vehicle_id FK NULL
reminder_type
title
message
reminder_date
reminder_time
priority
status
reference_id
reference_type
created_by
created_at
updated_at
```

## notifications

```text
id UUID PK
user_id FK NULL
customer_id FK NULL
showroom_id FK
title
message
notification_type
reference_id
reference_type
is_read
sent_at
created_at
```

## accounts

```text
id UUID PK
showroom_id FK
account_code
account_name
account_type
parent_account_id FK NULL
status
created_at
updated_at
```

## accounting_transactions

```text
id UUID PK
showroom_id FK
transaction_date
reference_type
reference_id
description
created_by
created_at
```

## accounting_entries

```text
id UUID PK
transaction_id FK
account_id FK
debit
credit
description
created_at
```

## attachments

```text
id UUID PK
showroom_id FK
entity_type
entity_id
file_name
file_url
file_type
file_size
uploaded_by
created_at
```

## audit_logs

```text
id UUID PK
showroom_id FK NULL
user_id FK
module
action
table_name
record_id
old_data JSONB
new_data JSONB
ip_address
user_agent
created_at
```

---

# 47. Database Indexing

Create indexes on:

```text
showroom_id
customer_id
product_id
vehicle_id
invoice_id
sale_id
loan_id
service_id
payment_date
sale_date
purchase_date
service_date
due_date
registration_number
chassis_number
engine_number
phone
email
status
created_at
```

Composite indexes:

```text
(showroom_id, status)
(showroom_id, sale_date)
(showroom_id, service_date)
(showroom_id, customer_id)
(showroom_id, due_date)
(showroom_id, created_at)
```

---

# 48. Database Constraints

Use:

```text
Foreign Keys
Unique Constraints
Check Constraints
Not Null
Default Values
```

Important unique values:

```text
showrooms.code
users.auth_user_id
inventory.stock_code
inventory.chassis_number
inventory.engine_number
customers.customer_code
sales.sale_number per showroom
invoices.invoice_number per showroom
purchases.purchase_number per showroom
payments.payment_number per showroom
service_records.service_number per showroom
loans.loan_number
(loan_id, emi_number)
```

Use appropriate `RESTRICT` behavior for financial records.

Do not use unsafe cascading deletion.

---

# 49. Supabase RLS

Enable RLS on all tenant/business tables.

Core rule:

```text
auth.uid()
      ↓
users
      ↓
showroom_id
      ↓
allowed record
```

Create database helper functions such as:

```text
is_super_admin()
can_access_showroom(showroom_id)
has_permission(module, action)
```

RLS must control:

```text
SELECT
INSERT
UPDATE
DELETE
```

Do not rely only on Flutter permissions.

SUPER ADMIN:

```text
All showrooms
All modules
```

Normal users:

```text
Only assigned showroom(s)
Only permitted actions
```

Be careful to implement security-definer helper functions safely and prevent recursive RLS evaluation.

---

# 50. Database Functions / RPC

Create server-side functions for critical transactions.

At minimum:

```text
calculate_emi()
generate_emi_schedule()
create_sale_transaction()
record_payment()
complete_service()
transfer_inventory()
create_purchase_transaction()
create_expense_transaction()
create_accounting_transaction()
create_emi_reminders()
create_service_reminders()
```

Critical sale operation should preferably be:

```text
create_sale_transaction()
```

and execute atomically:

```text
Validate Customer
Validate Inventory
Create Sale
Create Sale Items
Reserve/Sell Inventory
Create Customer Vehicle
Create Invoice
Create Invoice Items
Create Payment
Create Loan if required
Generate EMI Schedule if required
Create Warranty
Create Free Service Schedule
Create Accounting Entries
Create Reminders
```

If an operation fails, rollback the transaction.

---

# 51. Reporting Views

Create optimized SQL views/functions for:

```text
daily_sales_summary
monthly_sales_summary
showroom_profit_summary
customer_outstanding_summary
emi_due_summary
emi_overdue_summary
service_revenue_summary
inventory_summary
purchase_summary
expense_summary
```

Do not duplicate transactional data unnecessarily.

---

# 52. Automatic Triggers

Use triggers for appropriate automatic operations:

```text
updated_at
audit logging where appropriate
profile creation after auth signup
business validations
derived status where safe
```

Do not hide complex financial logic inside uncontrolled triggers.

Prefer explicit RPC/database transactions for major business operations.

---

# 53. Supabase Storage Security

Use private buckets wherever documents contain sensitive data.

Suggested buckets:

```text
product-images
customer-documents
vehicle-documents
invoice-documents
service-documents
insurance-documents
warranty-documents
expense-attachments
```

Use:

```text
Storage RLS
Signed URLs
Role/showroom restrictions
```

Do not expose confidential customer or financial documents publicly.

---

# 54. Firebase Notifications

Implement FCM token management.

Create a suitable device token model/table:

```text
id
user_id
device_token
platform
device_name
is_active
last_seen_at
created_at
updated_at
```

Support multiple devices per user.

When user logs in:

```text
Get FCM Token
↓
Save Token
↓
Associate User
↓
Update last_seen
```

On logout:

```text
Deactivate current token
```

---

# 55. Error Handling

Create centralized application errors.

Example:

```dart
class AppException implements Exception {
  final String message;
  final String? code;

  AppException({
    required this.message,
    this.code,
  });
}
```

Create error mapping for:

```text
DioException
PostgrestException
AuthException
StorageException
Timeout
SocketException
Validation
Permission
Unauthorized
Forbidden
Not Found
Conflict
```

Display friendly messages using centralized snackbar/dialog helpers.

---

# 56. Logging

Create centralized logger.

Support levels:

```text
debug
info
warning
error
critical
```

Never log:

```text
passwords
tokens
service keys
financial secrets
private document URLs
```

Use environment-aware logging.

---

# 57. Environment Configuration

Support:

```text
development
staging
production
```

Configuration must be separated.

Never hardcode production secrets into source code.

Use:

```text
--dart-define
environment configuration
CI/CD secrets
```

---

# 58. Testing

Create tests for:

```text
Models
Validators
Repositories
Controllers
Business functions
EMI calculation
Pagination
Permission checks
Date calculations
Inventory calculations
Accounting calculations
```

Widget tests for:

```text
Login
Dashboard
Customer List
Customer Form
Sales Form
Invoice
Service Form
EMI
Reports
```

Integration tests for:

```text
Login
Create Customer
Add Inventory
Create Sale
Generate Invoice
Receive Payment
Create Loan
Generate EMI
Book Service
Complete Service
Create Expense
Generate Reports
```

---

# 59. Performance

Optimize:

```text
Pagination
Lazy loading
Image caching
Database indexes
SQL queries
Realtime subscriptions
Rebuild frequency
GetX reactive updates
List rendering
Desktop tables
Web performance
```

Avoid:

```text
unnecessary Obx rebuilds
huge lists in memory
repeated identical API calls
duplicate queries
large image uploads
```

Use caching where beneficial.

---

# 60. Responsive Tables

For Web/Windows use:

```text
Paginated Data Table
Data Grid
Column Sorting
Column Visibility
Filtering
Export
```

For mobile:

```text
Cards
Compact List
Bottom Sheet Filters
Expandable Rows
```

Do not force desktop tables onto mobile screens.

---

# 61. Customer 360 View

Customer details page must become a complete customer dashboard.

Sections:

```text
Profile
Vehicles
Sales
Invoices
Payments
Finance
EMIs
Services
Warranty
Insurance
Reminders
Documents
Timeline
Outstanding
```

Timeline should show:

```text
Sale
Invoice
Payment
Loan
EMI
Service
Warranty
Insurance
Reminder
```

---

# 62. Vehicle 360 View

Vehicle details should show:

```text
Bike Information
Customer
Chassis
Engine
Registration
Sale
Invoice
Payments
Loan
EMI
Warranty
Insurance
Service History
Upcoming Service
Free Services
Documents
```

---

# 63. Sales Transaction Flow

Implement this flow as an atomic server-side transaction:

```text
Create Sale
↓
Validate Inventory
↓
Allocate Bike
↓
Create Customer Vehicle
↓
Generate Invoice
↓
Record Initial Payment
↓
Create Finance
↓
Generate EMI Schedule
↓
Create Warranty
↓
Create Free Service Schedule
↓
Create Accounting
↓
Create Reminders
```

Do not leave partial transactions.

---

# 64. Service Transaction Flow

```text
Create Job Card
↓
Vehicle Reception
↓
Inspection
↓
Assign Technician
↓
Add Parts
↓
Add Labour
↓
Calculate Tax
↓
Apply Discount
↓
Complete Service
↓
Generate Invoice
↓
Receive Payment
↓
Update Vehicle
↓
Schedule Next Service
↓
Create Reminder
↓
Create Accounting
```

---

# 65. Purchase Transaction Flow

```text
Create Purchase
↓
Create Purchase Items
↓
Generate Inventory
↓
Update Stock
↓
Record Supplier Payable
↓
Record Payment
↓
Accounting Entries
```

---

# 66. Expense Transaction Flow

```text
Create Expense
↓
Approval
↓
Payment
↓
Accounting Entry
↓
Attachment
↓
Audit Log
```

---

# 67. Financial Integrity

Never allow:

```text
negative inventory without explicit configuration
payment > outstanding unless advance/refund logic exists
duplicate invoice numbers
duplicate chassis
duplicate engine numbers
unbalanced accounting transaction
invalid EMI totals
invalid showroom access
```

Use database constraints wherever possible.

---

# 68. Data Consistency

The same data must not be duplicated across unrelated entities.

Examples:

```text
Customer → single source
Vehicle → single source
Product → single source
Inventory → single source
Invoice → single source
Payment → single source
Loan → single source
EMI → single source
```

Use foreign keys.

Avoid storing duplicate customer/vehicle/payment information unnecessarily.

---

# 69. Auditability

Every important financial operation must be traceable:

```text
Who
What
When
Which showroom
Which record
Old value
New value
```

Audit history must remain available even if business records are cancelled.

---

# 70. UI Pages

Create at minimum:

## Authentication

```text
Splash
Login
Forgot Password
Reset Password
```

## Dashboard

```text
Dashboard
```

## Showroom

```text
Showroom List
Add Showroom
Edit Showroom
Showroom Details
```

## Users

```text
User List
Add User
Edit User
User Details
Role Assignment
Permission Management
```

## Products

```text
Product List
Add Product
Edit Product
Product Details
Product Images
Product Colors
```

## Inventory

```text
Inventory List
Inventory Details
Stock Transfer
Stock Adjustment
Stock History
```

## Customers

```text
Customer List
Add Customer
Edit Customer
Customer Details
Vehicle List
```

## Sales

```text
Sales List
Create Sale
Sale Details
Sale Approval
Sale Cancellation
```

## Billing

```text
Invoice List
Invoice Details
Invoice Preview
Print
PDF
Share
```

## Payments

```text
Payment List
Add Payment
Payment Details
Refund
```

## Finance

```text
Finance Company
Loan List
Loan Details
```

## EMI

```text
EMI Dashboard
EMI Schedule
Upcoming EMI
Overdue EMI
EMI Payment
EMI Receipt
```

## Purchases

```text
Supplier List
Purchase List
Create Purchase
Purchase Details
```

## Expenses

```text
Expense Categories
Expense List
Add Expense
Approval
Expense Details
```

## Services

```text
Service Booking
Job Cards
Service List
Service Details
Service Billing
Service History
```

## Free Service

```text
Free Service Plans
Vehicle Free Services
Due Services
Upcoming Services
```

## Warranty

```text
Warranty List
Warranty Details
Warranty Claims
```

## Insurance

```text
Insurance List
Insurance Details
Expiry List
```

## Reminders

```text
Reminder Dashboard
Reminder List
Upcoming
Overdue
Completed
```

## Reports

```text
Sales Report
Purchase Report
Expense Report
Profit & Loss
Stock Report
Payment Report
EMI Report
Service Report
Financial Summary
```

---

# 71. Global Search

Provide global search for:

```text
Customer
Phone
Vehicle Registration
Chassis
Engine
Invoice
Sale
Payment
Loan
EMI
Service
```

Search results should navigate directly to the corresponding entity.

---

# 72. Filters

Every list should support relevant filters:

```text
Showroom
Date Range
Status
Customer
Product
Payment Method
Salesperson
Service Advisor
Technician
Finance Company
```

---

# 73. Pagination

Default page size:

```text
20
```

Allow:

```text
20
50
100
```

where UI platform allows.

---

# 74. PDF / Export

Create reusable export services.

Support:

```text
Invoice PDF
Payment Receipt
EMI Receipt
Service Invoice
Sale Report
Purchase Report
Expense Report
Profit & Loss
Stock Report
Customer Statement
```

PDF layouts should be printable and professional.

---

# 75. Localization

Prepare architecture for localization.

Initial language:

```text
English
```

Structure should support future:

```text
Hindi
```

Do not hardcode user-visible strings throughout widgets.

Use localization resources.

---

# 76. Accessibility

Support:

```text
Readable font sizes
Good contrast
Keyboard navigation on desktop/web
Semantic labels
Touch-friendly controls
Focus management
Screen reader support where practical
```

---

# 77. Code Quality

Use:

```text
Strong typing
Null safety
Reusable classes
Single responsibility
Clear naming
Small controllers
Small widgets
Repository abstraction
No duplicated business logic
```

Avoid:

```text
God controllers
Huge widget files
Hardcoded IDs
Hardcoded showroom logic
Direct Supabase calls from widgets
Direct Dio calls from views
Business calculations inside UI
```

---

# 78. Documentation

Create project documentation:

```text
README.md
ARCHITECTURE.md
DATABASE.md
RBAC.md
OFFLINE_SYNC.md
DEPLOYMENT.md
API.md
TESTING.md
```

Document:

```text
How to run
How to configure Supabase
How to configure Firebase
How to run migrations
How to seed roles
How to seed permissions
How to create admin
How offline sync works
How to deploy
```

---

# 79. Supabase Migration Structure

Create executable migrations such as:

```text
supabase/
└── migrations/
    ├── 001_extensions.sql
    ├── 002_core_schema.sql
    ├── 003_business_schema.sql
    ├── 004_finance_service_schema.sql
    ├── 005_indexes.sql
    ├── 006_functions.sql
    ├── 007_triggers.sql
    ├── 008_roles_permissions.sql
    ├── 009_rls.sql
    ├── 010_storage.sql
    ├── 011_reporting_views.sql
    ├── 012_reminders.sql
    ├── 013_accounting.sql
    ├── 014_seed_data.sql
    └── 015_auth_triggers.sql
```

All migrations must execute successfully on a clean Supabase project.

Order dependencies correctly.

Never reference tables/functions before they exist.

---

# 80. SQL Migration Quality

Every migration must be:

```text
Executable
Idempotent where practical
Dependency-safe
Production-safe
Clearly documented
```

Use:

```sql
create extension if not exists ...
create table if not exists ...
create index if not exists ...
```

where appropriate.

Do not silently ignore dangerous migration failures.

---

# 81. Seed Data

Seed:

## Roles

```text
SUPER ADMIN
ADMIN
SHOWROOM MANAGER
ACCOUNT MANAGER
SALES MANAGER
SALES STAFF
SERVICE MANAGER
SERVICE ADVISOR
TECHNICIAN
INVENTORY MANAGER
PURCHASE MANAGER
ACCOUNTANT
VIEWER
```

## Permissions

Seed all required:

```text
view
create
edit
delete
approve
cancel
complete
export
print
manage
```

for relevant modules.

---

# 82. Default Accounting Accounts

Create reasonable default accounts such as:

```text
Cash
Bank
Customer Receivable
Inventory
Sales Revenue
Service Revenue
Purchase
Supplier Payable
Tax Payable
Discount
Salary Expense
Rent Expense
Marketing Expense
Other Expense
```

Every showroom should have its own accounting accounts where appropriate.

---

# 83. Supabase Auth Profile Trigger

After a new Supabase Auth user is created:

```text
auth.users
      ↓
users profile
```

Create the application user profile safely.

The user must still be assigned:

```text
showroom
role
permissions
```

through controlled onboarding/admin workflow.

---

# 84. Offline Sync Conflict Handling

When local data and server data conflict:

```text
Server version
Local version
Updated timestamps
Revision/version number
```

Use deterministic conflict rules.

For sensitive financial records:

```text
Do not automatically overwrite.
Mark conflict.
Require controlled resolution.
```

---

# 85. Security Principle

The application must follow:

```text
Flutter UI security
        +
GetX permission checks
        +
Supabase RLS
        +
Database constraints
        +
Server-side transactions
```

Security must never rely on Flutter alone.

---

# 86. Final Architecture

The complete system should conceptually follow:

```text
                 FLUTTER APPLICATION
                        │
        ┌───────────────┴───────────────┐
        │                               │
      GetX                           Common UI
        │
   Controllers
        │
   Repositories
        │
 ┌──────┴────────┐
 │               │
Remote         Local
 │               │
Supabase       Hive/SQLite
 │               │
 └──────┬────────┘
        │
     Sync Layer
        │
     Supabase
        │
 ┌──────┼───────────────┐
 │      │       │       │
Auth   DB    Storage   RPC
 │      │
 │     PostgreSQL
 │      │
 │     RLS
 │      │
 └──────┴────── Security
```

---

# 87. Development Rules

When generating code:

1. Give complete working code.
2. Do not provide pseudo-code unless explicitly requested.
3. Do not omit required imports.
4. Do not use undefined classes/functions.
5. Keep dependencies consistent.
6. Maintain the same architecture across all modules.
7. Reuse common components.
8. Avoid unnecessary duplication.
9. Ensure all code compiles logically.
10. Provide exact file paths for every generated file.
11. For database changes, provide executable migration SQL.
12. For major business transactions, prefer Supabase RPC/database transactions.
13. Do not break previously defined architecture.
14. Do not silently change database naming.
15. Explain why an architectural change is needed when it affects existing code.

---

# 88. Expected Development Approach

Develop the project in a controlled sequence:

```text
Phase 1
Project Setup
↓
Flutter Architecture
↓
Theme
↓
Routing
↓
GetX DI
↓
Dio
↓
Supabase
↓
Firebase
```

```text
Phase 2
Database
↓
Migrations
↓
Functions
↓
Triggers
↓
RLS
↓
Roles
↓
Permissions
```

```text
Phase 3
Authentication
↓
Users
↓
Roles
↓
Showrooms
↓
RBAC
```

```text
Phase 4
Products
↓
Inventory
↓
Customers
↓
Vehicles
```

```text
Phase 5
Sales
↓
Billing
↓
Payments
↓
Finance
↓
EMI
```

```text
Phase 6
Purchases
↓
Expenses
↓
Accounting
```

```text
Phase 7
Free Service
↓
Paid Service
↓
Warranty
↓
Insurance
```

```text
Phase 8
Reminders
↓
Notifications
↓
FCM
```

```text
Phase 9
Reports
↓
PDF
↓
Excel/CSV
↓
Export
```

```text
Phase 10
Offline
↓
Sync
↓
Conflict Resolution
```

```text
Phase 11
Testing
↓
Optimization
↓
Security Audit
↓
Deployment
```

---

# 89. Critical Requirement

Do not build every module independently in a disconnected manner.

Everything must remain connected through the central business model:

```text
SHOWROOM
    ↓
CUSTOMER
    ↓
VEHICLE
    ↓
SALE
    ↓
INVOICE
    ↓
PAYMENT
    ↓
FINANCE
    ↓
EMI
    ↓
SERVICE
    ↓
WARRANTY
    ↓
INSURANCE
    ↓
REMINDERS
    ↓
ACCOUNTING
    ↓
REPORTING
```

Inventory must connect to products and sales.

Accounting must connect to sales, purchases, payments, services, and expenses.

Reporting must be based on normalized transactional data.

Audit logging must preserve the history of important operations.

---

# 90. Final Goal

Deliver a complete enterprise-grade Bike Showroom Management System that is:

```text
Secure
Scalable
Responsive
Modular
Maintainable
Offline-capable
Multi-showroom
Role-based
Permission-based
Transaction-safe
Auditable
Financially consistent
Performance optimized
Supabase-powered
Flutter-powered
```

The final system should be capable of managing:

```text
Showrooms
Users
Roles
Permissions
Bikes
Products
Inventory
Customers
Vehicles
Sales
Billing
Invoices
Payments
Finance
EMI
Purchases
Suppliers
Expenses
Accounting
Free Service
Paid Service
Warranty
Insurance
Reminders
Notifications
Reports
Documents
Audit Logs
Offline Sync
```

Build it as a **real production ERP-style application**, not a basic CRUD demo.

Whenever generating implementation code, use the architecture and database structure defined in this master specification and keep all modules interconnected.
