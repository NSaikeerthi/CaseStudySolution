# CaseStudyAccountProject

## Project Overview
This project delivers a **Salesforce solution** for managing **Projects linked to Accounts**, with a strong focus on:

- Data integrity  
- Scalability  
- Performance (bulk-safe design)  
- User-friendly UI  

---

## Features

### Data Model
- **Custom Object:** `Project__c`
- **Fields:**
  - `Status__c` *(Picklist)*: Planned, Active, Completed  
  - `Budget__c` *(Currency)*  
- **Account Field:**
  - `Total_Projects__c` *(Number)* - maintains total related projects  

---

### Validation Rules
- Ensures **Budget > 0** when:
  - `Status__c = 'Active'`

---

### Apex Implementation (Trigger + Handler)

- Bulk-safe design (handles 200+ records)
- Uses **aggregate queries** for accuracy
- Prevents SOQL/DML inside loops
- Handles all DML events:
  - Insert  
  - Update  
  - Delete  
  - Undelete  
- Supports **re-parenting of Projects**
- Maintains `Total_Projects__c` on Account

---

### Test Classes

Comprehensive test coverage including:

- CRUD operations  
- Re-parenting scenarios  
- Bulk testing:
  - 200 records  
  - 500 records  
- Edge cases:
  - Null Account references  
- Focus on **meaningful assertions**, not just coverage  

---

### Lightning Web Component (LWC)

**Component:** `accountProjectList`

#### Features:
- Displays **Account details**
- Shows related **Projects in a table**
- Filter Projects by:
  - Status  
  - Active-only toggle  
- **Pagination support**
  - Efficient data loading  

---
##  Setup Instructions

- Deploy metadata
- Assign Permission Set
- Add LWC to Account Record Page (at your Account record page else use the custom app for verifying the solution)
- Create Projects and view in UI

For a detailed explaination and technical overview, please refer to the document-
[Case_Study_Solution_Documentation.pdf](https://github.com/user-attachments/files/27318039/Case_Study_Solution_Documentation.pdf)


## Author
**Sai Keerthi N**