ECHO<sup>®</sup> Open Plant API
========================

The ECHO Open Plant Database is an open-source, open-access database and API for interacting with plant/crop data collected by ECHO and its network members.

Access:
-------
This database is maintained by ECHO and contains both public and private records. Read access to public information is available to all. Records marked as private are available only to the record owner and governing organizations.

**HELP WANTED:** A license for this project need to be chosen and intellectual property policies and declarations need to be written. If you have expertise in these areas please contact ICT@echonet.org.


Some tools based on this database and API include:
--------------------------------------------------
- The ECHO Green Manure and Cover Crop Selection Tool
- ECHO Plant Information Sheets
- ECHO germplasm catalogs and ordering systems
- Plant sign generators


Project Status:
---------------
We are currently in the process of relocating the database and API to this standalone tool. This open-source project is the foundation for the second iteration of the database and encompasses these requirements:

**Full Localization**
- All text fields shall be translatable
- All data fields shall be populated in SI Units
- Each request shall specify the desired locale
- Responses indicate available locales when requested

**Record Ownership**
- All records shall have ownership
- All records shall have version tracking
- All records shall use UUIDs for unique identifiers

### API

**Standardized Access**
GraphQL

**Versioned**
- All changes to records shall have trackable histories

