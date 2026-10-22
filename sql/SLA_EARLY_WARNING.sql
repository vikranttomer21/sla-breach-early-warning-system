USE sla_early_warning;

SELECT 'staging' AS table_name, COUNT(*) AS row_count FROM support_tickets_staging
UNION ALL
SELECT 'production' AS table_name, COUNT(*) AS row_count FROM support_tickets;

DESCRIBE support_tickets;
USE sla_early_warning;

INSERT INTO support_tickets (
    ticket_id,
    opened_at,
    channel,
    queue,
    priority,
    subject,
    first_response_min,
    resolved_at,
    reopened,
    csat
)
SELECT
    NULLIF(TRIM(ticket_id), ''),
    STR_TO_DATE(NULLIF(TRIM(opened_at), ''), '%c/%e/%Y %H:%i'),
    NULLIF(TRIM(channel), ''),
    NULLIF(TRIM(queue), ''),
    NULLIF(TRIM(priority), ''),
    NULLIF(TRIM(subject), ''),
    CAST(NULLIF(TRIM(first_response_min), '') AS SIGNED),
    STR_TO_DATE(NULLIF(TRIM(resolved_at), ''), '%c/%e/%Y %H:%i'),
    CASE 
        WHEN LOWER(TRIM(reopened)) IN ('true', '1') THEN 1
        WHEN LOWER(TRIM(reopened)) IN ('false', '0') THEN 0
        ELSE NULL
    END,
    CAST(NULLIF(TRIM(csat), '') AS DECIMAL(3, 2))
FROM support_tickets_staging;
USE sla_early_warning;

SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT ticket_id) AS unique_tickets,
    SUM(CASE WHEN opened_at IS NULL THEN 1 ELSE 0 END) AS null_opened_at,
    SUM(CASE WHEN resolved_at IS NULL THEN 1 ELSE 0 END) AS null_resolved_at,
    SUM(CASE WHEN first_response_min IS NULL THEN 1 ELSE 0 END) AS null_first_response
FROM support_tickets;
USE sla_early_warning;

SELECT 
    queue,
    COUNT(*) AS total_tickets,
    ROUND(AVG(first_response_min), 1) AS avg_reply_time_min,
    SUM(CASE WHEN resolved_at IS NULL THEN 1 ELSE 0 END) AS open_tickets
FROM support_tickets
GROUP BY queue
ORDER BY avg_reply_time_min DESC;
USE sla_early_warning;

SELECT 
    priority,
    COUNT(*) AS total_tickets,
    ROUND(AVG(first_response_min), 1) AS avg_reply_time_min,
    SUM(CASE WHEN resolved_at IS NULL THEN 1 ELSE 0 END) AS open_tickets
FROM support_tickets
GROUP BY priority
ORDER BY avg_reply_time_min ASC;
USE sla_early_warning;

SELECT 
    queue,
    COUNT(first_response_min) AS tickets_with_response,
    SUM(CASE 
        WHEN priority = 'urgent' AND first_response_min > 30 THEN 1
        WHEN priority = 'high'   AND first_response_min > 60 THEN 1
        WHEN priority = 'normal' AND first_response_min > 120 THEN 1
        WHEN priority = 'low'    AND first_response_min > 240 THEN 1
        ELSE 0 
    END) AS total_breaches,
    ROUND(100.0 * SUM(CASE 
        WHEN priority = 'urgent' AND first_response_min > 30 THEN 1
        WHEN priority = 'high'   AND first_response_min > 60 THEN 1
        WHEN priority = 'normal' AND first_response_min > 120 THEN 1
        WHEN priority = 'low'    AND first_response_min > 240 THEN 1
        ELSE 0 
    END) / COUNT(first_response_min), 2) AS breach_rate_pct
FROM support_tickets
GROUP BY queue
ORDER BY breach_rate_pct DESC;
USE sla_early_warning;

DROP VIEW IF EXISTS vw_support_tickets_analytics;

CREATE VIEW vw_support_tickets_analytics AS
SELECT 
    ticket_id,
    opened_at,
    resolved_at,
    channel,
    queue,
    priority,
    subject,
    first_response_min,
    
    -- Operational Status
    CASE 
        WHEN resolved_at IS NULL THEN 'Unresolved (Backlog)'
        ELSE 'Resolved'
    END AS ticket_status,
    
    -- Turnaround metrics
    TIMESTAMPDIFF(MINUTE, opened_at, resolved_at) AS resolution_time_min,
    ROUND(TIMESTAMPDIFF(MINUTE, opened_at, resolved_at) / 60.0, 2) AS resolution_time_hrs,
    
    -- Modeled SLA Thresholds (Minutes)
    CASE 
        WHEN priority = 'urgent' THEN 30
        WHEN priority = 'high'   THEN 60
        WHEN priority = 'normal' THEN 120
        WHEN priority = 'low'    THEN 240
        ELSE NULL
    END AS target_sla_min,
    
    -- Modeled SLA Breach Flag
    CASE 
        WHEN first_response_min IS NULL THEN 'Pending / No Response'
        WHEN priority = 'urgent' AND first_response_min > 30  THEN 'Breached'
        WHEN priority = 'high'   AND first_response_min > 60  THEN 'Breached'
        WHEN priority = 'normal' AND first_response_min > 120 THEN 'Breached'
        WHEN priority = 'low'    AND first_response_min > 240 THEN 'Breached'
        ELSE 'Met Target'
    END AS sla_status,
    
    reopened,
    csat
FROM support_tickets;
SELECT 
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN sla_status = 'Breached' THEN 1 END) AS total_breaches,
    COUNT(CASE WHEN sla_status = 'Met Target' THEN 1 END) AS total_met,
    COUNT(CASE WHEN sla_status = 'Pending / No Response' THEN 1 END) AS total_pending,
    COUNT(CASE WHEN ticket_status = 'Unresolved (Backlog)' THEN 1 END) AS total_backlog
FROM vw_support_tickets_analytics;
SELECT * FROM vw_support_tickets_analytics;