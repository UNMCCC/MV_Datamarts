DROP PROCEDURE IF EXISTS sp_DM_Calendar;
CREATE PROCEDURE `sp_DM_Calendar`()
BEGIN
   /*************************************************************************************************************************************\
  **  Purpose:    Combine patient calendar(schedule) and event information including PHI for billing/finance purposes
  **  Issue:      When a patient is enrolled on a study a calendar is setup with multiple events as a plan to be marked Done
  **  Method:     Begin with Event Association, inner join Protocol Status, Event detail and Status tables,
                  then left join Person, Study, and Codelst to lookup descriptions,
                  then left join User to lookup names for audit fields (Event Association, Protocol Status, Event detail and Event Status)
  **  Exclusions: Only include Active/Reactivated calendar statuses (exclude: Work in Progress, Freeze, Deactivated, Offline for Editing)
                  Only include event statuses where no end date exists
                  Only include calendars associated after December 1, 2019 to exclude prior attempts to setup calendars in the past
  **  Aliases:    event_assoc = ea, sch_codelst = scl, sch_events1 = se1, sch_eventstat = ses, sch_protstat = sps
                  er_study = st, person = p, er_user = u
  ** Last update: 2020-Dec-01
  \*************************************************************************************************************************************/

/* Drop and Create table fresh -- this section below can be removed in the future once process is stablized */
DROP TABLE dm_calendar;
CREATE TABLE `dm_calendar` (
  `pkEventID_ea` int(11) DEFAULT NULL,
  `pkStudyID_st` int(11) DEFAULT NULL,
  `pkProtStat_sps` int(11) DEFAULT NULL,
  `pkEventID_se1` int(11) DEFAULT NULL,
  `pkEventStat_ses` int(11) DEFAULT NULL,
  
  `studyNumber_st` varchar(100) DEFAULT NULL,
  `studyTitle_st_lu`	varchar(1000),
  `eventTypeDefined_ea` varchar(100) DEFAULT NULL,
  `scheduleName_ea` varchar(4000) DEFAULT NULL,
  `scheduleDesc_ea` varchar(4000) DEFAULT NULL,
  
  `protStatDT_sps` date DEFAULT NULL,
  `calStatSubtype_sps_lu` varchar(4) DEFAULT NULL,
  `calStatDesc_sps_lu` varchar(200) DEFAULT NULL,
  `protStatNote_sps` varchar(200) DEFAULT NULL,
  
  `statusDesc_se1` varchar(200) DEFAULT NULL,
  `eventDesc_se1` varchar(100) DEFAULT NULL,
  `eventSequence_se1` int(11) DEFAULT NULL,
  `startDT_se1` date DEFAULT NULL,
  `endDT_se1` date DEFAULT NULL,
  `eventExeDT_se1` date DEFAULT NULL,
  `actualSchDT_se1` date DEFAULT NULL,
  `EventCoverageSubtype_se1_lu` varchar(4) DEFAULT NULL,
  `EventCoverageDesc_se1_lu` varchar(200) DEFAULT NULL,
  
  `pkPerson_p` int(11) DEFAULT NULL,
  `personCode_p` varchar(20) DEFAULT NULL,
  `patFirst_p` varchar(32) DEFAULT NULL,
  `patMiddle_p` varchar(32) DEFAULT NULL,
  `patLast_p` varchar(32) DEFAULT NULL,
  `birthDt_p` date DEFAULT NULL,
  
  `eventStatEndDT_ses` date DEFAULT NULL,
  `eventStatSubtype_ses_lu` varchar(4) DEFAULT NULL,
  `eventStatDesc_ses_lu` varchar(200) DEFAULT NULL,
  
  `createDt_ea` date DEFAULT NULL,
  `createByFName_ea` varchar(30) DEFAULT NULL,
  `createByLName_ea` varchar(30) DEFAULT NULL,
  `modDt_ea` date DEFAULT NULL,
  `modByFName_ea` varchar(30) DEFAULT NULL,
  `modByLName_ea` varchar(30) DEFAULT NULL,
  
  `createDt_se1` date DEFAULT NULL,
  `createByFName_se1` varchar(30) DEFAULT NULL,
  `createByLName_se1` varchar(30) DEFAULT NULL,
  `modDt_se1` date DEFAULT NULL,
  `modByFName_se1` varchar(30) DEFAULT NULL,
  `modByLName_se1` varchar(30) DEFAULT NULL,
    
  `createDt_ses` date DEFAULT NULL,
  `createByFName_ses` varchar(30) DEFAULT NULL,
  `createByLName_ses` varchar(30) DEFAULT NULL,
  `modDt_ses` date DEFAULT NULL,
  `modByFName_ses` varchar(30) DEFAULT NULL,
  `modByLName_ses` varchar(30) DEFAULT NULL,
  
  `createDt_sps` date DEFAULT NULL,
  `createByFName_sps` varchar(30) DEFAULT NULL,
  `createByLName_sps` varchar(30) DEFAULT NULL,
  `modDt_sps` date DEFAULT NULL,
  `modByFName_sps` varchar(30) DEFAULT NULL,
  `modByLName_sps` varchar(30) DEFAULT NULL,
  
  `xDMrunDt` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/* Drop and Create table fresh -- this section above can be removed in the future once process is stablized */

/* POPULATE TEMPORARY TABLE ************************************************************************************************************/
DROP TEMPORARY TABLE IF EXISTS temp_DM_Calendar;

CREATE TEMPORARY TABLE temp_DM_Calendar
SELECT
  /*  Table Primary Keys  */
  ea.EVENT_ID                                         AS pkEventID_ea, 
  st.PK_STUDY                                         AS pkStudyID_st,
  sps.PK_PROTSTAT                                     AS pkProtStat_sps,
  se1.EVENT_ID                                        AS pkEventID_se1,
  ses.PK_EVENTSTAT                                    AS pkEventStat_ses,
  
  /*  Details of protocol calendars associated with the study event_assoc table contains the details of protocol calendars associated 
      with the study. Once a calendar gets associated with the study, a copy of calendar as well as its events is maintained here. 
      Any subsequent changes in the calendar or events are stored in this table, not in event_def'                                     */
  st.STUDY_NUMBER                                     AS studyNumber_st, -- Study Number from er_study
  st.STUDY_TITLE                                      AS studyTitle_st, -- study title from er_study
  /* if additional study fields are requested in future they can be added here */
  CASE WHEN ea.EVENT_TYPE = 'P'
    THEN 'Calendar'
    ELSE 'Event associated to calendar'
    END                                               AS eventTypeDefined_ea,
  ea.NAME                                             AS scheduleName_ea,
  RTRIM(SUBSTRING(ea.DESCRIPTION,1,200))              AS scheduleDesc_ea,
  
  /*  Protocol calendar status details 'sch_protstat table stores the protocol calendar status details' */
  sps.PROTSTAT_DT                                     AS protStatDT_sps, -- 'this column stores the date when the status was entered'
  RTRIM(SUBSTRING(clCalStat.CODELST_SUBTYP,1,4))      AS calStatSubtype_sps_lu, -- 'this column stores the calendar status, pk_codelst of the sch_codelst table'
  RTRIM(SUBSTRING(clCalStat.CODELST_DESC,1,200))      AS calStatDesc_sps_lu, -- 'this column stores the calendar status, pk_codelst of the sch_codelst table'
  sps.PROTSTAT_NOTE                                   AS protStatNote_sps,
  
  /*  Patient schedule details 'sch_events1 table stores the patient schedule' */
  CASE WHEN se1.STATUS = 0
    THEN 'Current Schedule'
    ELSE 'Past Schedule'
    END                                               AS statusDesc_se1,
  se1.DESCRIPTION                                     AS eventDesc_se1,
  se1.EVENT_SEQUENCE                                  AS eventSequence_se1,
  se1.START_DATE_TIME                                 AS startDT_se1, -- 'This column stores the suggested Start Date of the event'
  se1.END_DATE_TIME                                   AS endDT_se1, -- 'This column stores the End Date of the event'
  se1.EVENT_EXEON                                     AS eventExeDT_se1, -- 'This column stores the start date of the latest status of the event.'
  se1.ACTUAL_SCHDATE                                  AS actualSchDT_se1, -- 'This column stores the actual scheduled date of the event'
  RTRIM(SUBSTRING(clCovType.CODELST_SUBTYP,1,4))      AS EventCoverageSubtype_se1_lu, /* 'This column stores the codelst id for the Coverage Type, stores the pk of er_codelst table' */
  RTRIM(SUBSTRING(clCovType.CODELST_DESC,1,200))      AS EventCoverageDesc_se1_lu, /* 'This column stores the codelst id for the Coverage Type, stores the pk of er_codelst table' */
  
  /*  Patient details 'This table stores complete patient demographics data' */
  p.PK_PERSON                                         AS pkPerson_p, -- primary key in Velos for the person
  p.PERSON_CODE                                       AS personCode_p, -- patient MRN (patients from NMCCA sites that are not at UNM this may be alphanumeric)
  p.PERSON_FNAME                                      AS patFirst_p, -- patient first name
  p.PERSON_MNAME                                      AS patMiddle_p, -- patient last name
  p.PERSON_LNAME                                      AS patLast_p, -- patient middle name
  p.PERSON_DOB                                        AS birthDt_p, -- patient date of birth
  
  /*  Status of the events associated 'This table stores the various status of the events associated to a study protocol' */
  ses.EVENTSTAT_ENDDT                                 AS eventStatEndDT_ses, /* 'This column stores the end date of event status. Intially this column has null value. It is set when the status is changed.' */
  RTRIM(SUBSTRING(clEStat.CODELST_SUBTYP,1,4))        AS eventStatSubtype_ses_lu, /* 'This column stores the status. Stores PK of sch_codelst for code type - eventstatus' */
  RTRIM(SUBSTRING(clEStat.CODELST_DESC,1,200))        AS eventStatDesc_ses_lu, /* 'This column stores the status. Stores PK of sch_codelst for code type - eventstatus' */
  
  /*  Audit information date/user created/modified fields for ea, se1, ses, sps*/  
  ea.CREATED_ON                                       AS createDt_ea,
  CreatorEAu.USR_FIRSTNAME                            AS createByFName_ea,
  CreatorEAu.USR_LASTNAME                             AS createByLName_ea,
  ea.LAST_MODIFIED_DATE                               AS modDt_ea,
  ModByEAu.USR_FIRSTNAME                              AS modByFName_ea,
  ModByEAu.USR_LASTNAME                               AS modByLName_ea,
  se1.CREATED_ON                                      AS createDt_se1,
  CreatorSe1u.USR_FIRSTNAME                           AS createByFName_se1,
  CreatorSe1u.USR_LASTNAME                            AS createByLName_se1,
  se1.LAST_MODIFIED_DATE                              AS modDt_se1,
  ModBySe1u.USR_FIRSTNAME                             AS modByFName_se1,
  ModBySe1u.USR_LASTNAME                              AS modByLName_se1,
  ses.CREATED_ON                                      AS createDt_ses,
  CreatorSesu.USR_FIRSTNAME                           AS createByFName_ses,
  CreatorSesu.USR_LASTNAME                            AS createByLName_ses,
  ses.LAST_MODIFIED_DATE                              AS modDt_ses,
  ModBySesu.USR_FIRSTNAME                             AS modByFName_ses,
  ModBySesu.USR_LASTNAME                              AS modByLName_ses,
  sps.CREATED_ON                                      AS createDt_sps,
  CreatorSpsu.USR_FIRSTNAME                           AS createByFName_sps,
  CreatorSpsu.USR_LASTNAME                            AS createByLName_sps,
  sps.LAST_MODIFIED_DATE                              AS modDt_sps,
  ModBySpsu.USR_FIRSTNAME                             AS modByFName_sps,
  ModBySpsu.USR_LASTNAME                              AS modByLName_sps,
  CURRENT_TIMESTAMP()                                 AS `xDMrunDt`
  
/***************************************************************************************************************************************/
FROM event_assoc AS ea -- begin from the event association table
  INNER JOIN sch_protstat   AS sps            ON ea.EVENT_ID = sps.FK_EVENT -- add matching protocol (study)
                                                  AND sps.FK_CODELST_CALSTAT IN ('285','288') -- AND only Active=285 or Reactivated=288
                                                  AND sps.PROTSTAT_DT >= date('2019-12-01') -- AND exclude before Dec 1, 2019
                                                  AND sps.pk_PROTSTAT =  -- AND limit to max pk_protstat when multiple active records exist
                                                      (SELECT MAX(sps2.pk_ProtStat) FROM sch_protstat sps2
                                                          WHERE sps2.FK_Event= sps.FK_Event AND sps2.FK_CODELST_CALSTAT =sps.FK_CODELST_CALSTAT) 
  INNER JOIN sch_events1    AS se1            ON ea.EVENT_ID = se1.SESSION_ID -- add matching events setup on calendar
  INNER JOIN sch_eventstat  AS ses            ON se1.EVENT_ID = ses.FK_EVENT -- add matching event statuses on calendar(Done, Not Done, etc. )
                                                  AND ses.EVENTSTAT_ENDDT IS NULL -- AND where end dates are NULL
  LEFT JOIN sch_codelst     AS clCalStat      ON sps.FK_CODELST_CALSTAT = clCalStat.PK_CODELST -- lookup calendar status description from codelst
  LEFT JOIN sch_codelst     AS clCovType      ON se1.FK_CODELST_COVERTYPE = clCovType.PK_CODELST -- lookup coverage type description from codelst
  LEFT JOIN sch_codelst     AS clEStat        ON ses.EVENTSTAT = clEstat.PK_CODELST -- lookup event status description from codelst
  LEFT JOIN person          AS p              ON se1.PATIENT_ID = p.PK_PERSON -- lookup patient name, DOB, person code (a.k.a MRN) from person
  LEFT JOIN er_study        AS st             ON ea.CHAIN_ID = st.PK_STUDY -- lookup study number, title (add other fields if requested)
  -- Add lookups for user names on audit fields (created by, modified by)
  LEFT JOIN er_user         AS CreatorEAu     ON ea.CREATOR            = CreatorEAu.PK_USER -- lookup event_assoc creator user
  LEFT JOIN er_user         AS ModByEAu       ON ea.LAST_MODIFIED_BY   = ModByEAu.PK_USER -- lookup event_assoc modified by user
  LEFT JOIN er_user         AS CreatorSe1u    ON Se1.CREATOR           = CreatorSe1u.PK_USER -- lookup sch_events1 creator user
  LEFT JOIN er_user         AS ModBySe1u      ON se1.LAST_MODIFIED_BY  = ModBySe1u.PK_USER -- lookup sch_events1 modified by user
  LEFT JOIN er_user         AS CreatorSesu    ON Ses.CREATOR           = CreatorSesu.PK_USER -- lookup sch_eventstat creator user
  LEFT JOIN er_user         AS ModBySesu      ON ses.LAST_MODIFIED_BY  = ModBySesu.PK_USER -- lookup sch_eventstat modified by user
  LEFT JOIN er_user         AS CreatorSpsu    ON Sps.CREATOR           = CreatorSpsu.PK_USER -- lookup sch_protstat creator user
  LEFT JOIN er_user         AS ModBySpsu      ON Sps.LAST_MODIFIED_BY  = ModBySpsu.PK_USER -- lookup sch_protstat modified by user
;
 
/* Clear table and populate from temp table */
TRUNCATE TABLE rc_mv_test.DM_Calendar;
INSERT INTO rc_mv_test.DM_Calendar
SELECT * FROM temp_DM_Calendar
;

/* Drop temporary tables created for use in this stored procedure */
DROP TABLE temp_DM_Calendar;
END;
