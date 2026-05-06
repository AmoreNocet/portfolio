/*
  КОГОРТНЫЙ RETENTION — месячные когорты по дате первого платежа

  Бизнес-цель: понять, как удерживаются платящие пользователи,
  и оценить эффект продуктовых изменений на retention.

  Метрика: доля пользователей когорты, совершивших хотя бы одну оплату
  в месяц M+N (где M — месяц первого платежа).

  Используется: DATE_TRUNC, оконные функции, FILTER, CROSSTAB-подобная логика через CASE
*/

-- Шаг 1: определяем когорту пользователя = месяц первого успешного платежа
WITH first_payment AS (
    SELECT
        user_id,
        DATE_TRUNC('month', MIN(paid_at))::date     AS cohort_month
    FROM payments
    WHERE status = 'success'
    GROUP BY user_id
),

-- Шаг 2: все успешные платежи с указанием месяца активности
user_activity AS (
    SELECT
        p.user_id,
        fp.cohort_month,
        DATE_TRUNC('month', p.paid_at)::date        AS activity_month,
        -- разница в месяцах относительно когортного месяца
        EXTRACT(YEAR  FROM AGE(DATE_TRUNC('month', p.paid_at), fp.cohort_month)) * 12
        + EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', p.paid_at), fp.cohort_month))
                                                    AS months_since_cohort
    FROM payments p
    JOIN first_payment fp USING (user_id)
    WHERE p.status = 'success'
),

-- Шаг 3: размер каждой когорты (M0 = 100%)
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT user_id) AS cohort_size
    FROM first_payment
    GROUP BY cohort_month
)

-- Итоговая retention-матрица (M0 … M11)
SELECT
    ua.cohort_month,
    cs.cohort_size                                          AS m0_users,
    -- M0 всегда = 100%
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_cohort = 0  THEN ua.user_id END) / cs.cohort_size, 1) AS m0,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_cohort = 1  THEN ua.user_id END) / cs.cohort_size, 1) AS m1,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_cohort = 2  THEN ua.user_id END) / cs.cohort_size, 1) AS m2,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_cohort = 3  THEN ua.user_id END) / cs.cohort_size, 1) AS m3,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_cohort = 4  THEN ua.user_id END) / cs.cohort_size, 1) AS m4,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_cohort = 5  THEN ua.user_id END) / cs.cohort_size, 1) AS m5,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN months_since_cohort = 6  THEN ua.user_id END) / cs.cohort_size, 1) AS m6
FROM user_activity ua
JOIN cohort_sizes cs USING (cohort_month)
WHERE ua.cohort_month >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY ua.cohort_month, cs.cohort_size
ORDER BY ua.cohort_month;


-- ── Дополнительно: средний retention по всем когортам последних 6 мес ───────
WITH first_payment AS (
    SELECT user_id, DATE_TRUNC('month', MIN(paid_at))::date AS cohort_month
    FROM payments WHERE status = 'success' GROUP BY user_id
),
user_activity AS (
    SELECT
        p.user_id,
        fp.cohort_month,
        EXTRACT(YEAR FROM AGE(DATE_TRUNC('month', p.paid_at), fp.cohort_month)) * 12
        + EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', p.paid_at), fp.cohort_month)) AS months_since_cohort
    FROM payments p
    JOIN first_payment fp USING (user_id)
    WHERE p.status = 'success'
      AND fp.cohort_month >= CURRENT_DATE - INTERVAL '6 months'
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT user_id) AS cohort_size
    FROM first_payment
    WHERE cohort_month >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY cohort_month
)
SELECT
    ua.months_since_cohort                                    AS month_number,
    SUM(cs.cohort_size)                                       AS total_cohort_users,
    COUNT(DISTINCT ua.user_id)                                AS retained_users,
    ROUND(100.0 * COUNT(DISTINCT ua.user_id) / SUM(cs.cohort_size), 1) AS avg_retention_pct
FROM user_activity ua
JOIN cohort_sizes cs USING (cohort_month)
GROUP BY ua.months_since_cohort
HAVING ua.months_since_cohort <= 6
ORDER BY ua.months_since_cohort;
