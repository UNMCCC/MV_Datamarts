DROP PROCEDURE IF EXISTS minivelos.sp_DM_Study_Team;
CREATE PROCEDURE minivelos.`sp_DM_Study_Team`()
BEGIN
   /*******************************************************************************************************************************  
   **  Purpose:    Gather study team information as related to study with organization (site) details
   **  Issue:      Study team members will contain all associted to a study (both Active and Deactivated)
   **  Method:     Being with study team table, add left joins to study and other tables as needed 
                   Assumption a user can have only one default organization (site) assigned
   **  Exclusions: Active studies in ref_study_exclusions
   **  Aliases:    sttm = studyteam, st = study, u = user, s = site, stsi = studysites
   **  
   **  Last update date: 2020-Oct-19
   *****************************************************************************************************************************/
   
DROP TEMPORARY TABLE IF EXISTS temp_PrimaryRoleCnt;
CREATE TEMPORARY TABLE temp_PrimaryRoleCnt
SELECT -- count number of active primary role records
  FK_STUDY,
  COUNT(PK_STUDYTEAM) AS PrimaryRole_CNT
FROM er_studyteam
WHERE
  FK_CODELST_TMROLE IN('9','8130','8132','8211','12087') -- note change this list to match the one in the main select of this sp
  AND STUDYTEAM_STATUS = 'Active'
GROUP BY FK_STUDY
;   
   
DROP TEMPORARY TABLE IF EXISTS temp_DM_study_team;
CREATE TEMPORARY TABLE temp_DM_study_team
/**********************************************************************************************************************************/
SELECT
  /*  Table Primary Keys */
	sttm.PK_STUDYTEAM 			                                  AS pkStudyTeam_sttm,
  st.PK_STUDY                                               AS pkStudy_st,
	sttmUser.PK_USER 			                                    AS pkUser_sttmUser,
  sttmUser.FK_SITEID                                        AS fkSiteID_sttmUser,
  s.SITE_PARENT                                             AS fkSiteParent_s,

  /* Study identifiers -- additional fields and reference table lookups can be found in dm_study */
  st.STUDY_NUMBER                                           AS studyNumber_st,  -- aka protocol ID, local protocol ID
  stPI.usr_firstName                                        AS piFirst_st_lu,
  stPI.usr_lastName                                         AS piLast_st_lu,
  CONCAT(stPI.usr_firstName,' ',stPI.usr_lastName)          AS piName_st_lu,
  st.study_otherprinv	                                      AS piOther_st, -- free text field "If Other" on UI
  stCoord.usr_firstname                                     AS contactFirst_st_lu,
  stCoord.usr_lastname                                      AS contactLast_st_lu, -- st.study_coordinator is on UI as "Study Contact",  
  CONCAT(stCoord.usr_firstname,' ',stCoord.usr_lastname)    AS contactName_st_lu,
  st.STUDY_TITLE                                            AS title_st,
  
  /* Study Team identifiers */
  sttmUser.USR_FIRSTNAME                                    AS First_sttm_lu,
  sttmUser.USR_LASTNAME                                     AS Last_sttm_lu,
  CONCAT(sttmUser.USR_FIRSTNAME,' ',sttmUser.USR_LASTNAME)  AS Name_sttm_lu,
  RTRIM(SUBSTRING(sttmRole.CODELST_DESC,1,50))              AS Role_sttm_lu,
  CASE WHEN sttm.STUDY_TEAM_USR_TYPE = 'S' 
    THEN 'Super User'
    ELSE 'Default' END                                      AS UserType_sttm, -- This column stores the team user type flag. Possible values: D - default user; S - super user
  CASE WHEN sttm.STUDY_SITEFLAG = 'S' 
    THEN 'Specified Organzations' 
    ELSE 'Access to All Child Organizations' END            AS SiteFlag_sttm, -- This column stores the flag for study team user's multi organization settings: A - access to all child organizations  S - access to specified organizations (default)
  RTRIM(SUBSTRING(sttm.STUDYTEAM_STATUS,1,25))              AS Status_sttm, -- This column stores the current status of the team member
  RTRIM(SUBSTRING(sttm.STUDY_TEAM_RIGHTS,1,50))             AS Rights_sttm, -- The coded string of rights for the study team member

	/* Study Site identifiers */
  RTRIM(SUBSTRING(sType.codelst_desc,1,25))                 AS siteType_stst_lu,
  RTRIM(SUBSTRING(s.SITE_NAME,1,50))                        AS Organization_s,
  CAST(stsi.studysite_lsamplesize AS unsigned)              AS sampleSizeLocal_stsi,
  RTRIM(SUBSTRING(sParent.SITE_NAME,1,50))                  AS OrganizationParent_s,

  /* Audit information */       
  CASE WHEN sttm.FK_CODELST_TMROLE IN('9','8130','8132','8211','12087') -- Determine if Primary Role per CRO regulatory manager as of Sep 2020
    /* code='role name',
      9 = 'Principal Investigator',
      8130 = 'Primary Research Coordinator',
      8132 = 'Primary Regulatory Coordinator',
      8211 = 'Primary Data Coordinator',
      12087 = 'Primary Lab Technician' */
    THEN 'Y'
    ELSE 'N'
  END                                                               AS PrimaryRole_sttm,
  tPRCnt.PrimaryRole_CNT,
    CASE 
    WHEN sttmUser.USR_STAT = 'A' THEN 'Active'
    WHEN sttmUser.USR_STAT = 'D' THEN 'Deactivated'
    WHEN sttmUser.USR_STAT = 'B' THEN 'Blocked'
    ELSE ''
  END                                                               AS VelosAcctStatus_u, -- added 10/19/2020
  CASE 
    WHEN sttmUser.USR_TYPE = 'N' THEN 'Non-System'
    WHEN sttmUser.USR_TYPE = 'S' THEN 'System'
    WHEN sttmUser.USR_TYPE = 'X' THEN 'Deleted'
    WHEN sttmUser.USR_TYPE = 'P' THEN 'Portal'
    ELSE ''
  END                                                               AS VelosAcctType_u, -- added 10/19/2020
  sttmUser.CREATED_ON                                               AS createDt_u,
  CONCAT(uCreated.USR_FIRSTNAME,' ',uCreated.USR_LASTNAME)          AS createByName_u_lu,
  stsi.CREATED_ON                                                   AS createDt_stsi,
  CONCAT(stsiCreateby.USR_FIRSTNAME,' ',stsiCreateby.USR_LASTNAME)  AS createByName_stsi_lu,
  stsi.LAST_MODIFIED_ON 	                                          AS modDt_stsi,
  CONCAT(stsiModby.USR_FIRSTNAME,' ',stsiModby.USR_LASTNAME)        AS modByName_stsi_lu,
  sttm.CREATED_ON 			                                            AS createDt_sttm,
  CONCAT(sttmCreateby.USR_FIRSTNAME,' ',sttmCreateby.USR_LASTNAME)  AS createByName_sttm_lu,
	sttm.LAST_MODIFIED_DATE 	                                        AS modDt_sttm, -- UI seems to have a bug where moddate can exist without a mod by user???
  CONCAT(sttmModby.USR_FIRSTNAME,' ',sttmModby.USR_LASTNAME)        AS modByName_sttm_lu,
  CURRENT_TIMESTAMP()                                               AS xDMrunDt
/**********************************************************************************************************************************/
FROM er_studyteam sttm
  LEFT JOIN temp_PrimaryRoleCnt   tPRCnt        ON sttm.FK_STUDY          = tPRCnt.FK_STUDY -- get count of primary roles by study
  LEFT JOIN er_study              st            ON sttm.FK_STUDY          = st.PK_STUDY -- get Study Number
  LEFT JOIN er_user               stCoord			  ON st.study_coordinator	  = stCoord.pk_user -- get study contact
  LEFT JOIN er_user               stPI		      ON st.study_prInv			    = stPI.pk_user -- get pi
  LEFT JOIN er_user 			        sttmUser      ON sttm.FK_USER           = sttmUser.PK_USER -- user info
  LEFT JOIN er_user 			        uCreated      ON sttmUser.CREATOR       = uCreated.PK_USER -- user created
  LEFT JOIN er_site               s             ON sttmUser.FK_SITEID     = s.PK_SITE -- site info
  LEFT JOIN er_studysites         stsi          ON sttm.FK_STUDY          = stsi.FK_STUDY AND s.PK_SITE = stsi.FK_SITE -- local samplesize
  LEFT JOIN er_user 			        stsiCreateby  ON stsi.CREATOR           = stsiCreateby.PK_USER -- get createBy user
  LEFT JOIN er_user 			        stsiModby     ON stsi.LAST_MODIFIED_BY  = stsiModby.PK_USER -- get modby user for site
  LEFT JOIN er_codelst            sType         ON s.fk_codelst_type      = sType.pk_codelst -- lookup for site type
  LEFT JOIN er_site               sParent       ON s.SITE_PARENT          = sParent.PK_SITE  -- parent site info
  LEFT JOIN er_codelst 		        sttmRole 	    ON sttm.FK_CODELST_TMROLE = sttmRole.PK_CODELST -- lookup for role description
  LEFT JOIN er_user 			        sttmCreateby 	ON sttm.CREATOR           = sttmCreateby.PK_USER -- get createBy user for study team user
  LEFT JOIN er_user 			        sttmModby 		ON sttm.LAST_MODIFIED_BY  = sttmModby.PK_USER -- get modBy user for study team user

WHERE NOT EXISTS (SELECT * FROM ref_study_exclusions rse WHERE rse.IS_ACTIVE ='Y' AND rse.PK_STUDY = sttm.FK_STUDY) -- exclude studies from ref table which are IsActive=Y
/**********************************************************************************************************************************/
;

/* BEGIN POPULATE TABLE  */
TRUNCATE TABLE minivelos.dm_study_team;
INSERT INTO minivelos.dm_study_team
SELECT * FROM temp_DM_study_team
;

/* Drop temporary tables created for use in this stored procedure */
DROP TABLE temp_DM_study_team;
DROP TABLE temp_PrimaryRoleCnt;

/**********************************************************************************************************************************/
END;

