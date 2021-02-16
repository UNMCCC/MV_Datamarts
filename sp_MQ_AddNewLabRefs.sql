DROP PROCEDURE IF EXISTS sp_MQ_AddNewLabRefs;
CREATE PROCEDURE `sp_MQ_AddNewLabRefs`()
BEGIN

/********************************************************************************************************************************************\
  --  Name:         sp_MQ_AddNewLabRefs
  --  Depends on:   mq_labs, ref_labs_cpts
  --  Calls:
  --  Called by:    sp_DM_MQ_PharmaPats_YDA
  --  Description:  Attempts to address any new labs
  --  Uses:         Adds labs to reference table as Unknown status on a go forward basis
  --  Method:       Left join from exported labs to reference table
  --  Criteria:     map_status is null
  --  Note:         May need to review periodically for duplicates, errors, corrections etc.
  --  Aliases:      mq_labs=a, ref_labs_cpts=b
  --  Group:        Finance/Billing
  --  Project:      Velos Calendars
  --  Author:       Rick Compton
  --  Created:      February 2021
  --  Modified:                    
  --  Formerly:     
\*********************************************************************************************************************************************/

/** Find labs from daily MQ export that are not in ref table **/
DROP TEMPORARY TABLE IF EXISTS tempMissingLabs;
CREATE TEMPORARY TABLE tempMissingLabs
SELECT DISTINCT
  0 AS lc_idx, -- placeholder for the primary key to be auto-incremented by table
  a.lab_name AS labdesc,
  a.lab_code AS labname_mq,
  b.cpt,
  '' AS cpt_additional,
  '' AS labname_tricore,
  'Unknown' AS map_status,
  'Auto'  AS comments,
  CURRENT_TIMESTAMP() AS createDtTm,
  NULL AS modDtTm
FROM mq_labs a
LEFT JOIN ref_labs_cpts b ON a.lab_name = b.labdesc
WHERE b.map_status IS NULL
;

/** Insert temp table above into the reference table **/
INSERT INTO ref_labs_cpts
SELECT * from tempMissingLabs;

/** Drop temporary tables created for use in this stored procedure **/
DROP TABLE tempMissingLabs;

END;