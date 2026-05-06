/*
  ПРОДУКТОВЫЕ МЕТРИКИ: DAU / WAU / MAU, Stickiness, ARPU

  Бизнес-цель: еженедельный срез "здоровья" продукта для Product-команды.
  Этот запрос — основа BI-дашборда (Power BI / Looker Studio).

  Используется: DATE_TRUNC, оконные функции, LAG для расчёта WoW
*/

-- ── DAU / WAU / MAU и Stickiness ────────────────────────────────────────────
WITH daily_active AS (
    SELECT
        created_at::date                                    AS event_date,
        COUNT(DISTINCT user_id)                             AS dau
    FROM events
    WHERE event_type != 'registration'                       -- исключаем технические события
      AND created_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY event_date
),
weekly_active AS (
    SELECT
        DATE_TRUNC('week', created_at)::date                AS week_start,
        COUNT(DISTINCT user_id)                             AS wau
    FROM events
    WHERE event_type != 'registration'
      AND created_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY week_start
),
monthly_active AS (
    SELECT
        DATE_TRUNC('month', created_at)::date               AS month_start,
        COUNT(DISTINCT user_id)                             AS mau
    FROM events
    WHERE event_type != 'registration'
      AND created_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY month_start
)

-- Stickiness = DAU/MAU (скользящее среднее за 7 дней / MAU текущего месяца)
SELECT
    d.event_date,
    d.dau,
    m.mau,
    ROUND(100.0 * d.dau / NULLIF(m.mau, 0), 1)             AS stickiness_pct,
    -- WoW изменение DAU
    LAG(d.dau, 7) OVER (ORDER BY d.event_date)              AS dau_7d_ago,
    ROUND(100.0 * (d.dau - LAG(d.dau, 7) OVER (ORDER BY d.event_date))
        / NULLIF(LAG(d.dau, 7) OVER (ORDER BY d.event_date), 0), 1) AS dau_wow_pct
FROM daily_active d
LEFT JOIN monthly_active m
    ON DATE_TRUNC('month', d.event_date)::date = m.month_start
ORDER BY d.event_date;


-- ── ARPU и выручка: ежемесячно ──────────────────────────────────────────────
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', paid_at)::date                  AS month_start,
        COUNT(DISTINCT user_id)                             AS paying_users,
        SUM(amount)                                         AS revenue,
        ROUND(SUM(amount) / COUNT(DISTINCT user_id), 2)     AS arpu
    FROM payments
    WHERE status = 'success'
      AND paid_at >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY month_start
)
SELECT
    month_start,
    paying_users,
    ROUND(revenue, 0)                                       AS revenue,
    arpu,
    -- MoM рост выручки
    LAG(revenue) OVER (ORDER BY month_start)                AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
        / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0), 1) AS revenue_mom_pct
FROM monthly_revenue
ORDER BY month_start;


-- ── Feature Adoption Rate: топ-5 событий ────────────────────────────────────
SELECT
    event_type,
    COUNT(DISTINCT user_id)                                 AS unique_users,
    COUNT(*)                                                AS total_events,
    ROUND(100.0 * COUNT(DISTINCT user_id)
        / (SELECT COUNT(DISTINCT user_id) FROM events
           WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'), 1) AS adoption_rate_pct
FROM events
WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
  AND event_type != 'registration'
GROUP BY event_type
ORDER BY unique_users DESC
LIMIT 10;
