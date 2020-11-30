DROP PROCEDURE IF EXISTS minivelos.sp_DM_Calendar;
CREATE PROCEDURE minivelos.`sp_DM_Calendar`()
BEGIN
   /**************************************************************************************************************************\
  **  Purpose:    Combine patient calendar(schedule) and event information including PHI for billing/finance purposes
  **  Issue:      When a patient is enrolled on a study calendar is setup with multiple events planned to be marked Done
  **  Method:     Begin with Event Association, inner join Protocol Statu and Event detail,
                  then left join event status, Person, Study and schedule codelst as needed for code descriptions
  **  Exclusions: Only Active/Reactivated calendar statuses (exclude: Work in Progress, Freeze, Deactivated, Offline for Editing)
                  Only schedules that are Currently assigned to patient (past schedules for historical purpose in application)
                  Only include event status where no end date exists                  
                  Only include claendars associated after December 1, 2019
  **  Aliases:    event_assoc = ea, sch_codelst = scl, sch_events1 = se1, 
                  sch_eventstat = ses, sch_eventusr = seu, sch_protstat = sps
                  er_study = st, person = p 
  ** Last update date: 2020-Nov-13
  \**************************************************************************************************************************/
   
/* POPULATE TEMPORARY TABLE *************************************************************************************************/
DROP TEMPORARY TABLE IF EXISTS temp_DM_Calendar;

CREATE TEMPORARY TABLE temp_DM_Calendar
SELECT
  /*  Table Primary Keys  */
  ea.EVENT_ID               AS pkEventID_ea, 
  st.PK_STUDY               AS pkStudyID_st,
  sps.PK_PROTSTAT           AS pkProtStat_sps,
  se1.EVENT_ID              AS pkEventID_se1,
  ses.PK_EVENTSTAT          AS pkEventStat_ses,
  
  /*  Details of protocol calendars associated with the study 
      'event_assoc table contains the details of protocol calendars associated with the study. 
      Once a calendar gets associated with the study, a copy of calendar as well as its events is maintained here. 
      Any subsequent changes in the calendar or events are stored in this table, not in event_def' */
  ea.CHAIN_ID               AS chainID_ea, -- 'This column stores the study id. Stores PK of er_study. Also stores the calendar id (event_id) to which the events are associated in case of events'
  st.STUDY_NUMBER           AS studyNumber_st, -- Study Number from er_study
  ea.EVENT_TYPE             AS eventType_ea, -- 'This column indicates whether the record is for calendar or event P-calendar, A-indicates the event is associated to a calendar'
  ea.NAME                   AS scheduleName_ea,
  ea.DESCRIPTION            AS scheduleDesc_ea,
  
  /*  Protocol calendar status details 'sch_protstat table stores the protocol calendar status details' */
  sps.PROTSTAT_DT           AS protStatDT_sps, -- 'This column stores the date when the status was entered'
  sps.FK_CODELST_CALSTAT,   -- field can be removed after validations
  clCalStat.CODELST_DESC    AS calStat_sps_lu, -- 'this column stores the calendar status, pk_codelst of the sch_codelst table'
  
  /*  Patient schedule details 'sch_events1 table stores the patient schedule' */
  se1.STATUS                AS status_se1, /* 'This column stores the current status of the schedule:
                                            0 - Indicates that this belongs to current schedule for a patient enrolled to a study
                                            5 - Indicates that this belongs to past schedule for a patient enrolled to a study */
  se1.DESCRIPTION           AS eventDesc_se1,
  se1.START_DATE_TIME       AS startDT_se1, -- 'This column stores the suggested Start Date of the event'
  se1.END_DATE_TIME         AS endDT_se1, -- 'This column stores the End Date of the event'
  se1.EVENT_EXEON           AS eventExeDT_se1, -- 'This column stores the start date of the latest status of the event.'
  se1.ACTUAL_SCHDATE        AS actualSchDT_se1, -- 'This column stores the actual scheduled date of the event'
  se1.VISIT                 AS visit_se1, -- 'This column stores the visit number for the event.'
  se1.FK_VISIT,             -- confirm in vist information may be helpful in validations
  se1.FK_CODELST_COVERTYPE, -- field can be removed after validations
  clCovType.CODELST_DESC    AS EventCoveragetype_se1_lu, -- 'This column stores the codelst id for the Coverage Type, stores the pk of er_codelst table'
  
  /*  Patient details 'This table stores complete patient demographics data.' */
  p.PK_PERSON               AS pkPerson_p,
  p.PERSON_CODE             AS personCode_p, -- This is the MRN
  p.PERSON_FNAME            AS patFirst_p,
  p.PERSON_MNAME            AS patMiddle_p,
  p.PERSON_LNAME            AS patLast_p,
  p.PERSON_DOB              AS birthDt_p, -- This is the date of birth
  
  /*  Status of the events associated to a study protocol 'This table stores the various status of the events associated to a study protocol' */
  ses.EVENTSTAT_ENDDT       AS eventStatEndDT_ses, -- 'This column stores the end date of event status. Intially this column has null value. It is set when the status is changed.'
  ses.EVENTSTAT             AS fkStat_ses,  -- field can be removed after validations
  clEStat.CODELST_DESC      AS eventStat_ses_lu, -- 'This column stores the status. Stores PK of sch_codelst for code type - eventstatus'
  
  /*  Audit information -- add date/user created/modified fields if needed  */  
  CURRENT_TIMESTAMP()       AS `xDMrunDt`
  
/****************************************************************************************************************************/
FROM event_assoc AS ea
  INNER JOIN sch_protstat   AS sps       ON ea.EVENT_ID = sps.FK_EVENT -- add study association
                                            AND sps.FK_CODELST_CALSTAT IN ('285','288') -- AND only Active=285 or Reactivated=288
                                            AND sps.PROTSTAT_DT >= date('2019-12-01') -- AND exclude before Dec 1, 2019
                                            AND sps.pk_PROTSTAT =  -- AND limit to max pk_protstat when multile exist
                                                (SELECT MAX(sps2.pk_ProtStat) FROM sch_protstat sps2
                                                    WHERE sps2.FK_Event= sps.FK_Event AND sps2.FK_CODELST_CALSTAT =sps.FK_CODELST_CALSTAT) 
  INNER JOIN sch_events1    AS se1        ON ea.EVENT_ID = se1.SESSION_ID
                                            AND se1.STATUS = '0' -- add event description AND where status is Current = 0
  LEFT JOIN sch_eventstat   AS ses        ON se1.EVENT_ID = ses.FK_EVENT 
                                            AND ses.EVENTSTAT_ENDDT IS NULL -- add event status (Done, Not Done) AND without end date
  LEFT JOIN sch_codelst     AS clCalStat  ON sps.FK_CODELST_CALSTAT = clCalStat.PK_CODELST -- lookup calendar status description
  LEFT JOIN sch_codelst     AS clCovType  ON se1.FK_CODELST_COVERTYPE = clCovType.PK_CODELST -- lookup coverage type description
  LEFT JOIN sch_codelst     AS clEStat    ON ses.EVENTSTAT = clEstat.PK_CODELST -- lookup event status description
  LEFT JOIN person          AS p          ON se1.PATIENT_ID = p.PK_PERSON -- add person information including person code (a.k.a MRN)
  LEFT JOIN er_study        AS st         ON ea.CHAIN_ID = st.PK_STUDY -- add study number (add other fields if needed)
  
  /*  TESTING specific criteria study/calendar/event
  WHERE
  -- sps.FK_CODELST_CALSTAT IN ('285','288')-- limit to Active or Reactivated calendar status -- confirm with SME?
  -- AND se1.STATUS = '0' -- limit to Current schedule, excludes 5 which belongs to a past schedule -- confirm with SME?
  --  AND ses.EVENTSTAT_ENDDT IS NULL -- limit to events status end date NULL
  -- AND ea.CHAIN_ID = '4709' -- study number = Pharm RAD1901-308
  -- AND ea.EVENT_ID = '35229' -- testing event 35229
  -- AND se1.EVENT_ID LIKE '%41664' -- e.g. only one record for max protstat = 963
  */
;
 
TRUNCATE TABLE minivelos.DM_Calendar;
INSERT INTO minivelos.DM_Calendar
SELECT * from temp_DM_Calendar
;

/* Drop temporary tables created for use in this stored procedure */
DROP TABLE temp_DM_Calendar;
END
;