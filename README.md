# MV DataMart Stored Procedures
This is a set of stored procedures to populate content in staging environment that helps the financial department managing the clinical trials as well as the clinical research office tracking clinical trial entrollments.  

Specifically, these are stored procedures that merge data coming from several systems (EMR, CTMS).  Data consists of patients enrolled in clinical trials who recently had appointments, labs and infusions.  Extracts from here, help the team ensure whether the study or patient's insurance is responsible for charges.  

Before clinical informatics merged these extracts, the CRO financial department had to consolidate data from 3 systems and multiple screens per patient in each system.

These work in tandem with extracts from :
eVelos, the UNMCCC Clinical Trial Management System
Mosaiq, the UNMCCC Electronic Health System
  by Mosaiq proxy, the TriCore labs and the Cerner EMR (UNM Health system EHS mothership).

Nightly extracts from the systems above, and the datamarts produce ultimately a number of reports for the UNMCCC CRO fiscal department. For more info, contact UNMCCC CRO or Rick C. For technical aspects, contact the UNMCCC Informatics, or Inigo S.
