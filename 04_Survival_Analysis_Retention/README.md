# Python-проект: Survival Analysis — Анализ времени до оттока

## Бизнес-кейс

**Контекст:** Churn Prediction (проект 03) отвечает на вопрос *"кто уйдёт?"*.
Survival Analysis отвечает на более глубокий вопрос: **"когда и почему?"**

Product Manager хочет понять:
1. Какова медианная «жизнь» платящего пользователя?
2. Существенно ли отличается retention у разных тарифов (basic / pro / enterprise)?
3. Какие факторы *ускоряют* отток, а какие *замедляют* — с поправкой на все остальные переменные?

**Почему Survival Analysis, а не обычный Cohort Retention?**
- Обычный cohort retention работает с фиксированными временными окнами (M1, M2 и тд).
  Survival Analysis учитывает **цензурирование** — пользователей, которые ещё не ушли
  (мы знаем, что они живы сейчас, но не знаем, когда уйдут).
- Cox regression даёт **hazard ratios** — количественную меру влияния каждого фактора
  на скорость оттока, аналогично тому, как это делается в медицинских исследованиях.

## Что делает ноутбук

1. **Генерация данных** — когорта из 3 000 пользователей с датами входа и выхода (с цензурированием)
2. **Kaplan-Meier** — survival curves для всей базы и разбивка по тарифам + log-rank test
3. **Nelson-Aalen** — cumulative hazard (скорость накопления риска)
4. **Cox Proportional Hazards** — multivariate model, hazard ratios с CI, проверка PH assumption
5. **Предсказание индивидуальных кривых** — Cox предсказывает survival для конкретного профиля пользователя
6. **Бизнес-интерпретация** — перевод hazard ratio в язык продукта и CRM-рекомендации

## Стек

- Python 3.10+
- lifelines, pandas, numpy, matplotlib, seaborn
- Не требует внешних данных

## Запуск

```bash
pip install lifelines pandas numpy matplotlib seaborn
jupyter notebook survival_analysis.ipynb
```
