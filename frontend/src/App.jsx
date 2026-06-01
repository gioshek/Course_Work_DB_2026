import { useEffect, useState } from "react";
import { BrowserRouter, Link, Route, Routes, useNavigate, useParams } from "react-router-dom";
import { api } from "./api";
import "./App.css";

const DEFAULT_USER_ID = 2;
const DEFAULT_COVER_URL = "/covers/default.jpg";
const CURRENT_USER_KEY = "bookstream-current-user";

function getCurrentUser() {
  const rawUser = localStorage.getItem(CURRENT_USER_KEY);

  if (!rawUser) {
    return null;
  }

  try {
    return JSON.parse(rawUser);
  } catch {
    return null;
  }
}

function saveCurrentUser(user) {
  localStorage.setItem(CURRENT_USER_KEY, JSON.stringify(user));
}

function clearCurrentUser() {
  localStorage.removeItem(CURRENT_USER_KEY);
}

function getCurrentUserId() {
  const user = getCurrentUser();
  return user?.UserId || DEFAULT_USER_ID;
}

function isAdminUser(user) {
  if (!user) {
    return false;
  }

  const roleName = String(user.RoleName || "").toLowerCase();

  return (
    user.UserId === 1 ||
    roleName === "admin" ||
    roleName === "administrator" ||
    roleName === "администратор"
  );
}

function formatMoney(value) {
  const numberValue = Number(value || 0);

  return `${numberValue.toFixed(2)} ₽`;
}

function getBasePrice(book) {
  return Number(book?.Price || 0);
}

function getFinalPrice(book) {
  const basePrice = getBasePrice(book);
  const rawFinalPrice = book?.FinalPrice;

  if (rawFinalPrice === undefined || rawFinalPrice === null) {
    return basePrice;
  }

  return Number(rawFinalPrice || 0);
}

function getDiscountPercent(book) {
  return Number(book?.DiscountPercent || 0);
}

function hasBookDiscount(book) {
  if (!book || book.IsFree) {
    return false;
  }

  const basePrice = getBasePrice(book);
  const finalPrice = getFinalPrice(book);
  const discountPercent = getDiscountPercent(book);

  return discountPercent > 0 && finalPrice < basePrice;
}

function PriceDisplay({ book, large = false }) {
  if (!book) {
    return null;
  }

  if (book.IsFree) {
    return <div className={large ? "price price-large" : "price"}>Бесплатно</div>;
  }

  const basePrice = getBasePrice(book);
  const finalPrice = getFinalPrice(book);
  const discountPercent = getDiscountPercent(book);
  const hasDiscount = hasBookDiscount(book);

  if (!hasDiscount) {
    return (
      <div className={large ? "price price-large" : "price"}>
        {formatMoney(basePrice)}
      </div>
    );
  }

  return (
    <div className={large ? "price price-large price-discount" : "price price-discount"}>
      <span className="old-price">{formatMoney(basePrice)}</span>
      <span className="new-price">{formatMoney(finalPrice)}</span>
      <span className="discount-badge">−{discountPercent.toFixed(0)}%</span>
      {book.ActivePromotionName && (
        <span className="promotion-name">{book.ActivePromotionName}</span>
      )}
    </div>
  );
}


function BookAccessBadge({ book }) {
  if (!book) {
    return null;
  }

  if (book.IsFree) {
    return <span className="access-badge free-access">Бесплатная книга</span>;
  }

  if (book.IsPremium) {
    return <span className="access-badge premium-access">Премиальная · только покупка</span>;
  }

  if (book.IsAvailableBySubscription) {
    return <span className="access-badge subscription-access">Доступна по подписке</span>;
  }

  return <span className="access-badge purchase-access">Только покупка</span>;
}

const SQL_OBJECT_TYPE_ORDER = [
  "VIEW",
  "SQL_STORED_PROCEDURE",
  "SQL_SCALAR_FUNCTION",
  "SQL_INLINE_TABLE_VALUED_FUNCTION",
  "SQL_TABLE_VALUED_FUNCTION",
  "SQL_TRIGGER",
];

const SQL_OBJECT_TYPE_LABELS = {
  VIEW: "Представления",
  SQL_STORED_PROCEDURE: "Хранимые процедуры",
  SQL_SCALAR_FUNCTION: "Скалярные функции",
  SQL_INLINE_TABLE_VALUED_FUNCTION: "Табличные функции",
  SQL_TABLE_VALUED_FUNCTION: "Табличные функции",
  SQL_TRIGGER: "Триггеры",
};

const SQL_OBJECT_TYPE_DESCRIPTIONS = {
  VIEW: "Готовые виртуальные таблицы для чтения данных: каталог, отзывы, платежи, библиотека и популярность книг.",
  SQL_STORED_PROCEDURE: "Сценарии бизнес-операций и отчётов: покупка, каталог, подписки, админские отчёты и управление акциями.",
  SQL_SCALAR_FUNCTION: "Функции, которые возвращают одно значение: баланс, рейтинг, количество отзывов, активная скидка, итоговая цена.",
  SQL_INLINE_TABLE_VALUED_FUNCTION: "Функции, которые возвращают таблицу и могут использоваться в SELECT-запросах.",
  SQL_TABLE_VALUED_FUNCTION: "Функции, которые возвращают таблицу и могут использоваться в SELECT-запросах.",
  SQL_TRIGGER: "Автоматические обработчики изменений таблиц. Они заполняют AuditLog и показывают работу триггеров БД.",
};

const SQL_OBJECT_EXPLANATIONS = {
  "vw_BookCatalog": {
    "summary": "Готовая выборка каталога: книга, авторы, жанры, цена, премиальность, рейтинг и действующая скидка.",
    "details": "Представление объединяет Book, Publisher, BookAuthor, Author и BookGenre, а рейтинг и количество отзывов получает через SQL-функции. Для каждой книги оно также рассчитывает автоматическую скидку и итоговую цену. Backend использует его через usp_GetBookCatalog и usp_GetBookById, а админские отчёты — для анализа книг."
  },
  "vw_ActiveBookPromotions": {
    "summary": "Показывает активные акции и книги, на которые они распространяются.",
    "details": "Представление разворачивает активные акции на книги. Для обычной акции учитываются записи BookPromotion, а для глобальной акции — все книги. Оно используется процедурой usp_GetDatabaseDashboard при формировании блока действующих акций в административной панели."
  },
  "vw_BookReviews": {
    "summary": "Отзывы с названиями книг и именами пользователей.",
    "details": "Представление объединяет Review, Book и UserAccount. Благодаря ему карточка книги получает не только идентификаторы, но и понятные данные: название произведения, имя пользователя, оценку, текст и дату отзыва. Используется в usp_GetBookById."
  },
  "vw_ActiveUserSubscriptions": {
    "summary": "Только действующие на текущую дату подписки пользователей.",
    "details": "Представление соединяет UserSubscription, UserAccount и SubscriptionPlan и оставляет только активные подписки, срок которых ещё не истёк. Используется в профиле пользователя и на административной панели."
  },
  "vw_UserLibrary": {
    "summary": "Вычисляемая библиотека пользователя без отдельной таблицы доступа.",
    "details": "Представление формирует доступные пользователю книги: купленные, бесплатные и доступные по активной подписке. Премиальные книги не открываются по подписке. Backend читает библиотеку прямо из этого представления для раздела «Моя библиотека»."
  },
  "vw_UserReadingProgress": {
    "summary": "Прогресс чтения пользователей по конкретным книгам.",
    "details": "Представление объединяет ReadingProgress, UserAccount и Book. Оно возвращает текущую страницу, число страниц и процент чтения. Используется процедурой профиля пользователя и административной аналитикой."
  },
  "vw_PopularBooks": {
    "summary": "Сводная популярность книг по покупкам, избранному, отзывам и рейтингу.",
    "details": "Представление считает агрегаты по Book, Purchase, FavoriteBook и Review. Оно используется в обзорной статистике администратора, чтобы показать наиболее востребованные произведения."
  },
  "vw_UserPayments": {
    "summary": "История платежей с пользователем, назначением и текущим балансом.",
    "details": "Представление связывает Payment с UserAccount и определяет назначение платежа: покупка, подписка или пополнение. Текущий баланс берётся через fn_GetUserBalance. Используется в профиле пользователя."
  },
  "usp_HealthCheck": {
    "summary": "Проверяет подключение API к BookStreamDB.",
    "details": "Короткая служебная процедура возвращает имя базы данных и текущее время SQL Server. Endpoint /health использует её для быстрой проверки работоспособности backend и соединения с БД."
  },
  "usp_RegisterUser": {
    "summary": "Регистрирует нового пользователя с датой рождения.",
    "details": "Процедура проверяет уникальность Username и Email, находит роль обычного пользователя и создаёт UserAccount. Дата рождения сохраняется для персонального промокода BIRTHDAY15."
  },
  "usp_GetUserForLogin": {
    "summary": "Находит пользователя для входа по Username или Email.",
    "details": "Процедура возвращает данные пользователя, роль, баланс и хеш пароля. Backend сравнивает введённый пароль и сохраняет текущего пользователя в интерфейсе."
  },
  "usp_GetSubscriptionPlans": {
    "summary": "Возвращает доступные тарифы подписки.",
    "details": "Процедура выбирает активные записи SubscriptionPlan. Используется страницей подписок, чтобы показывать название, цену, длительность и описание тарифа."
  },
  "usp_TopUpBalance": {
    "summary": "Пополняет баланс и создаёт запись о платеже.",
    "details": "Процедура валидирует положительную сумму, обновляет UserAccount.Balance и вставляет Payment в одной транзакции. Backend вызывает её из профиля пользователя вместо дублирования SQL в Python."
  },
  "usp_CreateSubscription": {
    "summary": "Оформляет подписку с оплатой из внутреннего баланса.",
    "details": "Процедура проверяет тариф, пользователя и достаточность средств, списывает стоимость, создаёт Payment и UserSubscription в одной транзакции. Backend вызывает её со страницы подписок."
  },
  "usp_GetUserProfile": {
    "summary": "Собирает личный кабинет пользователя несколькими результатами.",
    "details": "Процедура возвращает профиль, статистику покупок и избранного, дату рождения, персональный birthday-промокод, активные подписки, историю платежей и прогресс чтения. Используется страницей профиля."
  },
  "usp_GetUserFavorites": {
    "summary": "Возвращает избранные книги пользователя.",
    "details": "Процедура соединяет FavoriteBook с vw_BookCatalog, поэтому карточки избранного получают обложку, цену, премиальность и данные о скидке."
  },
  "usp_AddFavoriteBook": {
    "summary": "Добавляет книгу в избранное без дублей.",
    "details": "Процедура проверяет существование пользователя и книги, а затем создаёт запись FavoriteBook, только если такой пары ещё нет."
  },
  "usp_RemoveFavoriteBook": {
    "summary": "Удаляет книгу из избранного пользователя.",
    "details": "Процедура удаляет одну связь UserAccount — Book из FavoriteBook и возвращает подтверждение операции."
  },
  "usp_GetBookCatalog": {
    "summary": "Возвращает каталог книг с SQL-фильтрами.",
    "details": "Процедура читает vw_BookCatalog и умеет фильтровать по тексту, жанру, бесплатности, доступности по подписке и премиальности. Backend дополнительно выполняет нечёткий поиск RapidFuzz для запросов с опечатками."
  },
  "usp_GetBookById": {
    "summary": "Возвращает карточку книги и её отзывы.",
    "details": "Первым набором данных процедура возвращает одну книгу из vw_BookCatalog, вторым — отзывы из vw_BookReviews. Используется страницей произведения."
  },
  "usp_GetBookPricePreview": {
    "summary": "Предварительно рассчитывает цену с введённым промокодом.",
    "details": "Процедура проверяет книгу, рассчитывает подходящую скидку, применённый промокод и итоговую цену через SQL-функции. Страница книги вызывает её до покупки, чтобы показать пользователю результат ввода промокода."
  },
  "usp_BuyBook": {
    "summary": "Покупает книгу, списывает итоговую цену и фиксирует промокод.",
    "details": "Ключевая финансовая процедура. Она проверяет пользователя, книгу, повторную покупку и баланс; рассчитывает скидку и финальную цену; создаёт Payment и Purchase в одной транзакции. В Purchase сохраняются AppliedPromoCode и AppliedDiscountPercent."
  },
  "usp_GetBookContentForUser": {
    "summary": "Открывает текст книги только пользователю с доступом.",
    "details": "Процедура вызывает fn_UserHasAccessToBook, а затем возвращает BookContent и сохранённый ReadingProgress. Премиальная книга откроется только после покупки."
  },
  "usp_AddReview": {
    "summary": "Создаёт или обновляет отзыв пользователя.",
    "details": "Процедура сохраняет Rating и ReviewText. Триггер дополнительно проверяет доступ к книге и записывает действие в AuditLog."
  },
  "usp_UpdateReadingProgress": {
    "summary": "Сохраняет текущую страницу чтения.",
    "details": "Процедура проверяет номер страницы, рассчитывает процент через fn_CalculateReadingProgressPercent и создаёт либо обновляет ReadingProgress."
  },
  "usp_GetAdminUser": {
    "summary": "Проверяет, что запрос выполняет администратор.",
    "details": "Процедура находит активного пользователя с ролью Admin. Backend вызывает её перед административными endpoint-ами."
  },
  "usp_GetAdminOptions": {
    "summary": "Возвращает справочники для формы добавления книги.",
    "details": "Процедура отдаёт издательства, авторов и жанры тремя наборами данных. Админка использует их для выбора и поиска значений."
  },
  "usp_CreatePublisher": {
    "summary": "Создаёт издательство или возвращает существующее.",
    "details": "Процедура принимает название издательства и не создаёт дубликаты. Используется в справочнике админки."
  },
  "usp_CreateAuthor": {
    "summary": "Создаёт автора по имени и фамилии.",
    "details": "Процедура работает только с FirstName и LastName. Модель автора содержит ровно те данные, которые нужны каталогу и справочнику админки."
  },
  "usp_CreateGenre": {
    "summary": "Создаёт жанр или возвращает существующий.",
    "details": "Процедура добавляет запись Genre по названию и используется из формы администратора."
  },
  "usp_GetAuditLog": {
    "summary": "Возвращает последние действия из журнала БД.",
    "details": "Процедура читает AuditLog для отдельной вкладки администратора. Записи создаются триггерами при изменении основных сущностей."
  },
  "usp_GetAdminStats": {
    "summary": "Возвращает короткую статистику для обзора админки.",
    "details": "Процедура считает основные метрики и отдаёт популярные книги. Используется на стартовой вкладке административной панели."
  },
  "usp_GetPromotions": {
    "summary": "Возвращает акции, их книги и каталог для привязки.",
    "details": "Первый результат содержит все акции, второй — явно созданные связи BookPromotion, третий — список книг для выбора. Используется вкладкой управления скидками. Глобальная акция действует без отдельных записей BookPromotion."
  },
  "usp_CreatePromotion": {
    "summary": "Создаёт или обновляет обычную акцию.",
    "details": "Процедура валидирует название, промокод, размер скидки и период действия. Администратор может задать глобальную акцию для всех книг или привязать обычную акцию к выбранным книгам. Системную birthday-акцию интерфейс не изменяет."
  },
  "usp_AssignPromotionToBook": {
    "summary": "Привязывает обычную акцию к книге.",
    "details": "Процедура создаёт BookPromotion после проверки акции и книги. Для глобальных и системных акций отдельная привязка не нужна."
  },
  "usp_RemovePromotionFromBook": {
    "summary": "Убирает книгу из обычной акции.",
    "details": "Процедура удаляет одну запись BookPromotion, оставляя саму акцию. Изменение фиксируется триггером."
  },
  "usp_DeletePromotion": {
    "summary": "Удаляет пользовательскую акцию.",
    "details": "Процедура запрещает удаление системной birthday-акции, а обычную акцию удаляет вместе с BookPromotion по каскадному правилу внешнего ключа."
  },
  "usp_CreateBook": {
    "summary": "Создаёт книгу со связями, содержимым и признаками доступа.",
    "details": "Процедура создаёт Book, BookAuthor, BookGenre и BookContent в одной транзакции. Она сохраняет Description, обложку, премиальность и доступность по подписке; премиальная книга автоматически становится доступной только для покупки."
  },
  "usp_GetDatabaseDashboard": {
    "summary": "Собирает административную панель БД.",
    "details": "Процедура возвращает метрики по всем сущностям, последние платежи и покупки, лидеров продаж, популярные книги и жанры, активные подписки, акции, AuditLog и перечень SQL-объектов из sys.objects."
  },
  "usp_AdminSalesReport": {
    "summary": "Формирует продажи за период с группировкой.",
    "details": "Администратор задаёт даты и группировку по книгам, пользователям или дням. Процедура считает количество покупок, общую сумму и среднюю цену."
  },
  "usp_AdminBookReport": {
    "summary": "Формирует отчёт по книгам с фильтрами.",
    "details": "Процедура фильтрует книги по жанру, издательству, минимальному рейтингу, наличию скидки и премиальности. Она показывает цену, итоговую цену, рейтинг, отзывы и продажи."
  },
  "usp_AdminUserReport": {
    "summary": "Формирует отчёт по пользователям.",
    "details": "Процедура показывает роль, дату рождения, birthday-промокод, баланс, покупки, отзывы, избранное и наличие активной подписки. Есть фильтры по активности, датам регистрации и сумме покупок."
  },
  "usp_AdminGenreReport": {
    "summary": "Анализирует жанры по книгам, продажам и рейтингам.",
    "details": "Процедура группирует данные по Genre и считает книги, покупки, продажи, отзывы и средний рейтинг за выбранный период."
  },
  "usp_AdminAuditLogReport": {
    "summary": "Фильтрует журнал действий БД.",
    "details": "Процедура позволяет администратору выбрать таблицу, тип действия и период, а затем получить подходящие записи AuditLog."
  },
  "fn_GetBookAverageRating": {
    "summary": "Считает средний рейтинг книги.",
    "details": "Скалярная функция вычисляет AVG по Review. Используется в vw_BookCatalog и vw_PopularBooks, поэтому рейтинг виден в каталоге и отчётах."
  },
  "fn_GetBookReviewCount": {
    "summary": "Считает количество отзывов книги.",
    "details": "Скалярная функция выполняет COUNT по Review и используется в vw_BookCatalog."
  },
  "fn_GetUserPurchasedBookCount": {
    "summary": "Считает купленные пользователем книги.",
    "details": "Скалярная функция считает Purchase по UserId. Используется процедурой профиля."
  },
  "fn_GetUserFavoriteBookCount": {
    "summary": "Считает книги в избранном пользователя.",
    "details": "Скалярная функция считает FavoriteBook по UserId. Используется процедурой профиля."
  },
  "fn_GetUserBalance": {
    "summary": "Возвращает текущий баланс пользователя.",
    "details": "Скалярная функция читает UserAccount.Balance. Используется процедурами платежей, подписок, покупок, профиля и представлением vw_UserPayments."
  },
  "fn_UserHasActiveSubscription": {
    "summary": "Проверяет наличие действующей подписки.",
    "details": "Скалярная функция ищет активную UserSubscription на выбранную дату. Используется при проверке доступа к книгам и при формировании библиотеки."
  },
  "fn_UserHasAccessToBook": {
    "summary": "Проверяет право пользователя читать книгу.",
    "details": "Функция возвращает 1 для купленной или бесплатной книги, а также для обычной книги по активной подписке. Премиальные книги подпиской не открываются. Используется в vw_UserLibrary, читалке и триггерах."
  },
  "fn_CalculateReadingProgressPercent": {
    "summary": "Рассчитывает процент чтения.",
    "details": "Функция переводит текущую страницу и общее число страниц в процент от 0 до 100. Используется при сохранении прогресса."
  },
  "fn_GetBookActiveDiscountPercent": {
    "summary": "Находит лучшую автоматическую скидку книги.",
    "details": "Функция выбирает максимальную активную обычную скидку: глобальную или привязанную через BookPromotion. Birthday-промокод намеренно не применяется автоматически."
  },
  "fn_GetBirthdayPromoCode": {
    "summary": "Выдаёт birthday-промокод пользователю в день рождения.",
    "details": "Функция сравнивает месяц и день UserAccount.DateOfBirth с текущей датой и возвращает активный системный промокод BIRTHDAY15. Используется в профиле и отчёте пользователей."
  },
  "fn_IsPromoCodeApplicable": {
    "summary": "Проверяет, можно ли применить введённый промокод.",
    "details": "Функция проверяет срок действия акции, область применения к книге и дополнительные условия. Для BIRTHDAY15 она требует активного пользователя, у которого сегодня день рождения. Используется предварительным расчётом цены и процедурой покупки."
  },
  "fn_GetApplicableDiscountPercent": {
    "summary": "Выбирает лучшую скидку с учётом промокода.",
    "details": "Функция сравнивает автоматическую скидку книги и введённый промокод. Для birthday-промокода дополнительно проверяются UserId и дата рождения."
  },
  "fn_GetAppliedPromotionCode": {
    "summary": "Возвращает код реально применённой акции.",
    "details": "Функция определяет, какая акция дала максимальную скидку. Результат сохраняется в Purchase.AppliedPromoCode и показывается в предварительном расчёте цены."
  },
  "fn_GetBookFinalPrice": {
    "summary": "Рассчитывает итоговую цену книги.",
    "details": "Функция берёт базовую цену Book.Price и уменьшает её на лучшую допустимую скидку. Бесплатная книга всегда получает цену 0. Используется каталогом, preview цены и покупкой."
  },
  "trg_Book_AfterInsertUpdate": {
    "summary": "Записывает создание и изменение книги в AuditLog.",
    "details": "Триггер автоматически фиксирует операции INSERT и UPDATE над Book, чтобы администратор видел историю изменений каталога."
  },
  "trg_Payment_AfterInsertUpdate": {
    "summary": "Записывает операции с платежами в AuditLog.",
    "details": "Триггер фиксирует создание и изменение Payment: сумму, метод и статус."
  },
  "trg_Purchase_AfterInsert": {
    "summary": "Записывает покупку книги в AuditLog.",
    "details": "Триггер срабатывает после INSERT в Purchase и сохраняет пользователя, книгу, финальную стоимость и применённый промокод."
  },
  "trg_UserSubscription_AfterInsertUpdate": {
    "summary": "Записывает оформление и изменение подписки.",
    "details": "Триггер фиксирует операции с UserSubscription: пользователя, тариф, срок и активность."
  },
  "trg_Review_AfterInsertUpdate": {
    "summary": "Проверяет доступ к книге и журналирует отзыв.",
    "details": "Триггер не позволяет оставить отзыв без доступа к книге. После успешной проверки фиксирует INSERT или UPDATE Review в AuditLog."
  },
  "trg_ReadingProgress_AfterInsertUpdate": {
    "summary": "Проверяет доступ и журналирует прогресс чтения.",
    "details": "Триггер запрещает сохранять ReadingProgress для недоступной книги и записывает успешное изменение в AuditLog."
  },
  "trg_UserAccount_AfterDelete": {
    "summary": "Журналирует удаление пользователя.",
    "details": "Триггер сохраняет запись AuditLog при DELETE из UserAccount. В интерфейсе удаление пока не вынесено, но защита действует для SQL-операций."
  },
  "trg_Promotion_AfterInsertUpdate": {
    "summary": "Записывает создание и изменение акции.",
    "details": "Триггер фиксирует PromoCode, процент скидки и признаки глобальной, birthday- и системной акции."
  },
  "trg_BookPromotion_AfterInsertDelete": {
    "summary": "Журналирует привязку и отвязку книг от акций.",
    "details": "Триггер срабатывает на BookPromotion и показывает администратору историю изменения состава акции."
  }
};


function getSqlObjectTypeLabel(objectType) {
  return SQL_OBJECT_TYPE_LABELS[objectType] || objectType || "SQL-объект";
}

function getSqlObjectTypeDescription(objectType) {
  return SQL_OBJECT_TYPE_DESCRIPTIONS[objectType] || "SQL-объект базы данных, используемый в проекте.";
}

function getSqlObjectExplanation(object) {
  return SQL_OBJECT_EXPLANATIONS[object?.ObjectName] || null;
}

function getSqlObjectDescription(object) {
  return (
    getSqlObjectExplanation(object)?.summary ||
    "SQL-объект проекта, найденный в базе данных. Используется в структуре приложения, отчётах или служебной логике."
  );
}

function getSqlObjectFullDescription(object) {
  return (
    getSqlObjectExplanation(object)?.details ||
    "Для этого объекта пока не задано отдельное развёрнутое описание. Он найден автоматически через sys.objects и отображается в админке для инвентаризации SQL-части проекта. Чтобы точно определить его назначение, открой соответствующий SQL-файл и посмотри, какая процедура, функция, представление или триггер его создаёт."
  );
}

function groupSqlObjects(sqlObjects = []) {
  const groups = new Map();

  for (const object of sqlObjects) {
    const objectType = object.ObjectType || "OTHER";

    if (!groups.has(objectType)) {
      groups.set(objectType, []);
    }

    groups.get(objectType).push(object);
  }

  const orderedTypes = [
    ...SQL_OBJECT_TYPE_ORDER,
    ...Array.from(groups.keys()).filter((objectType) => !SQL_OBJECT_TYPE_ORDER.includes(objectType)),
  ];

  return orderedTypes
    .filter((objectType) => groups.has(objectType))
    .map((objectType) => ({
      objectType,
      label: getSqlObjectTypeLabel(objectType),
      description: getSqlObjectTypeDescription(objectType),
      items: groups.get(objectType).sort((a, b) =>
        String(a.ObjectName || "").localeCompare(String(b.ObjectName || ""))
      ),
    }));
}


function SqlObjectDetailsModal({ object, onClose }) {
  useEffect(() => {
    if (!object) {
      return undefined;
    }

    function handleKeyDown(event) {
      if (event.key === "Escape") {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);

    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [object, onClose]);

  if (!object) {
    return null;
  }

  const fullDescription = getSqlObjectFullDescription(object);

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div
        className="modal-card sql-details-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="sql-object-modal-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="modal-header">
          <div>
            <span className="modal-kicker">{getSqlObjectTypeLabel(object.ObjectType)}</span>
            <h2 id="sql-object-modal-title">{object.ObjectName}</h2>
          </div>

          <button type="button" className="secondary small-button" onClick={onClose}>
            Закрыть
          </button>
        </div>

        <div className="sql-modal-summary">
          <strong>Кратко:</strong>
          <p>{getSqlObjectDescription(object)}</p>
        </div>

        <div className="sql-modal-section">
          <h3>Что делает объект</h3>
          <p>{fullDescription}</p>
        </div>

        <div className="sql-modal-meta">
          <span>Создан: {object.CreatedAt}</span>
          <span>Изменён: {object.ModifiedAt}</span>
        </div>
      </div>
    </div>
  );
}

function normalizeImageUrl(imageUrl) {
  if (!imageUrl) {
    return "";
  }

  if (imageUrl.startsWith("http://") || imageUrl.startsWith("https://")) {
    return imageUrl;
  }

  if (imageUrl.startsWith("/")) {
    return imageUrl;
  }

  return `/covers/${imageUrl}`;
}

function BookCover({ title, imageUrl, large = false }) {
  const customImageUrl = normalizeImageUrl(imageUrl);

  const [currentImageUrl, setCurrentImageUrl] = useState(
    customImageUrl || DEFAULT_COVER_URL
  );

  const [defaultImageFailed, setDefaultImageFailed] = useState(false);

  useEffect(() => {
    setCurrentImageUrl(customImageUrl || DEFAULT_COVER_URL);
    setDefaultImageFailed(false);
  }, [customImageUrl]);

  function handleImageError() {
    if (currentImageUrl !== DEFAULT_COVER_URL) {
      setCurrentImageUrl(DEFAULT_COVER_URL);
      return;
    }

    setDefaultImageFailed(true);
  }

  if (defaultImageFailed) {
    return (
      <div className={large ? "big-cover cover-placeholder" : "cover cover-placeholder"}>
        <span>{title ? title.slice(0, 1) : "К"}</span>
        <small>Нет изображения</small>
      </div>
    );
  }

  return (
    <div className={large ? "big-cover image-cover" : "cover image-cover"}>
      <img
        src={currentImageUrl}
        alt={title || "Обложка книги"}
        onError={handleImageError}
      />
    </div>
  );
}

function Layout({ children }) {
  const [theme, setTheme] = useState(() => {
    return localStorage.getItem("bookstream-theme") || "light";
  });

  const [currentUser, setCurrentUser] = useState(() => getCurrentUser());
  const [menuOpen, setMenuOpen] = useState(false);

  const currentUserId = currentUser?.UserId || DEFAULT_USER_ID;
  const isAdmin = isAdminUser(currentUser);

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("bookstream-theme", theme);
  }, [theme]);

  function logout() {
    clearCurrentUser();
    setCurrentUser(null);
    setMenuOpen(false);
    window.location.href = "/";
  }

  function closeMenu() {
    setMenuOpen(false);
  }

  return (
    <div className="app">
      <header className="header">
        <div className="header-topline">
          <Link to="/" className="logo" onClick={closeMenu}>BookStream</Link>

          <button
            type="button"
            className="menu-button secondary"
            aria-label={menuOpen ? "Закрыть меню" : "Открыть меню"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((oldValue) => !oldValue)}
          >
            <span className="menu-icon">{menuOpen ? "×" : "☰"}</span>
            <span>Меню</span>
          </button>
        </div>

        <nav className={menuOpen ? "nav nav-open" : "nav"}>
          <Link to="/" onClick={closeMenu}>Каталог</Link>
          <Link to={`/library/${currentUserId}`} onClick={closeMenu}>Моя библиотека</Link>
          <Link to={`/favorites/${currentUserId}`} onClick={closeMenu}>Избранное</Link>
          <Link to={`/profile/${currentUserId}`} onClick={closeMenu}>Профиль</Link>
          <Link to="/subscriptions" onClick={closeMenu}>Подписки</Link>

          {isAdmin && <Link to="/admin" onClick={closeMenu}>Админ-панель</Link>}

          {!currentUser && <Link to="/login" onClick={closeMenu}>Вход</Link>}
          <Link to="/register" onClick={closeMenu}>Регистрация</Link>
          <a
            href="http://127.0.0.1:8000/docs"
            target="_blank"
            rel="noreferrer"
            onClick={closeMenu}
          >
            API Docs
          </a>
        </nav>

        <div className={menuOpen ? "header-controls header-controls-open" : "header-controls"}>
          <select
            className="theme-select"
            value={theme}
            onChange={(e) => setTheme(e.target.value)}
            title="Тема сайта"
          >
            <option value="light">Светлая</option>
            <option value="paper">Бумажная</option>
            <option value="warm">Тёплая</option>
            <option value="gray">Серая</option>
            <option value="dark">Тёмная</option>
            <option value="night">Ночная</option>
          </select>

          {currentUser && (
            <div className="user-box">
              <span>
                {currentUser.Username}
                {isAdmin && " · Admin"}
              </span>

              <button type="button" className="secondary small-button" onClick={logout}>
                Выйти
              </button>
            </div>
          )}
        </div>
      </header>

      {menuOpen && <div className="mobile-menu-backdrop" onClick={closeMenu} />}

      <main className="main">{children}</main>
    </div>
  );
}
function CatalogPage() {
  const [books, setBooks] = useState([]);
  const [search, setSearch] = useState("");
  const [genre, setGenre] = useState("");
  const [onlyFree, setOnlyFree] = useState(false);
  const [onlyPremium, setOnlyPremium] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function loadBooks() {
    try {
      setLoading(true);
      setError("");

      const response = await api.get("/books/", {
        params: {
          search: search || undefined,
          genre: genre || undefined,
          only_free: onlyFree || undefined,
          only_premium: onlyPremium || undefined,
        },
      });

      setBooks(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadBooks();
  }, []);

  return (
    <Layout>
      <section className="hero">
        <div>
          <h1>Онлайн-сервис цифровых книг</h1>
          <p>
            Каталог электронных книг, покупки, подписки, отзывы и чтение прямо на сайте.
          </p>
        </div>
      </section>

      <section className="panel">
        <h2>Каталог книг</h2>

        <div className="filters">
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Поиск по названию, автору или описанию"
          />

          <input
            value={genre}
            onChange={(e) => setGenre(e.target.value)}
            placeholder="Жанр, например: Фантастика"
          />

          <label className="checkbox">
            <input
              type="checkbox"
              checked={onlyFree}
              onChange={(e) => setOnlyFree(e.target.checked)}
            />
            Только бесплатные
          </label>

          <label className="checkbox">
            <input
              type="checkbox"
              checked={onlyPremium}
              onChange={(e) => setOnlyPremium(e.target.checked)}
            />
            Только премиальные
          </label>

          <button onClick={loadBooks}>Найти</button>
        </div>

        {loading && <p>Загрузка...</p>}
        {error && <p className="error">{error}</p>}

        <div className="grid">
          {books.map((book) => (
            <article key={book.BookId} className="card">
              <BookCover title={book.Title} imageUrl={book.CoverImageUrl} />

              <div className="card-body">
                <h3>{book.Title}</h3>
                <p className="muted">{book.Authors}</p>
                <p>{book.Genres}</p>
                <BookAccessBadge book={book} />

                <div className="meta">
                  <span>{book.PublicationYear}</span>
                  <span>{book.PageCount} стр.</span>
                  <span>★ {Number(book.AverageRating).toFixed(1)}</span>
                </div>

                <PriceDisplay book={book} />

                <Link className="button-link" to={`/books/${book.BookId}`}>
                  Подробнее
                </Link>
              </div>
            </article>
          ))}
        </div>
      </section>
    </Layout>
  );
}

function BookDetailsPage() {
  const { bookId } = useParams();
  const navigate = useNavigate();

  const [bookData, setBookData] = useState(null);
  const [userId, setUserId] = useState(getCurrentUserId());
  const [rating, setRating] = useState(5);
  const [reviewText, setReviewText] = useState("");
  const [promoCode, setPromoCode] = useState("");
  const [pricePreview, setPricePreview] = useState(null);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function loadBook() {
    try {
      setError("");
      const response = await api.get(`/books/${bookId}`);
      setBookData(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  useEffect(() => {
    loadBook();
  }, [bookId]);

  async function buyBook() {
    try {
      setMessage("");
      setError("");

      const response = await api.post(`/books/${bookId}/purchase`, {
        user_id: Number(userId),
        payment_method: "Balance",
        promo_code: promoCode.trim() || null,
      });

      const newBalance = response.data?.Balance ?? response.data?.purchase?.Balance;

      if (newBalance !== undefined && newBalance !== null) {
        setMessage(`${response.data?.message || "Книга успешно куплена"}. Остаток баланса: ${formatMoney(newBalance)}.`);
      } else {
        setMessage(response.data?.message || "Книга успешно куплена.");
      }
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function checkPromoCode() {
    try {
      setMessage("");
      setError("");

      const response = await api.get(`/books/${bookId}/price-preview`, {
        params: {
          user_id: Number(userId),
          promo_code: promoCode.trim() || undefined,
        },
      });

      setPricePreview(response.data);

      if (promoCode.trim() && !response.data?.PromoCodeAccepted) {
        setError("Промокод недействителен для этой книги или пользователя.");
        return;
      }

      setMessage(`Итоговая цена: ${formatMoney(response.data?.FinalPrice)}.`);
    } catch (err) {
      setPricePreview(null);
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function addToFavorites() {
    try {
      setMessage("");
      setError("");

      await api.post(`/users/${Number(userId)}/favorites/${bookId}`);

      setMessage("Книга добавлена в избранное.");
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function addReview() {
    try {
      setMessage("");
      setError("");

      await api.post(`/books/${bookId}/reviews`, {
        user_id: Number(userId),
        rating: Number(rating),
        review_text: reviewText,
      });

      setMessage("Отзыв сохранён.");
      setReviewText("");
      loadBook();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  if (!bookData) {
    return (
      <Layout>
        <section className="panel">
          <p>Загрузка книги...</p>
          {error && <p className="error">{error}</p>}
        </section>
      </Layout>
    );
  }

  const book = bookData.book;
  const reviews = bookData.reviews || [];

  return (
    <Layout>
      <section className="panel book-details-panel">
        <div className="book-details-toolbar">
          <button className="secondary back-button" onClick={() => navigate("/")}>
            ← Назад в каталог
          </button>
        </div>

        <div className="book-page">
          <BookCover title={book.Title} imageUrl={book.CoverImageUrl} large />

          <div className="book-info">
            <h1>{book.Title}</h1>
            <p className="muted">{book.Authors}</p>
            <p>{book.Description}</p>
            <BookAccessBadge book={book} />

            <div className="details-meta">
              <span>Жанры: {book.Genres}</span>
              <span>Издательство: {book.PublisherName}</span>
              <span>Год: {book.PublicationYear}</span>
              <span>Возраст: {book.AgeLimit}+</span>
              <span>Страниц: {book.PageCount}</span>
              <span>Рейтинг: ★ {Number(book.AverageRating).toFixed(1)}</span>
            </div>

            {hasBookDiscount(book) && (
              <div className="promotion-banner">
                <strong>Акция:</strong> {book.ActivePromotionName || "скидка"}
                {book.ActivePromoCode && <span>Промокод: {book.ActivePromoCode}</span>}
              </div>
            )}

            <PriceDisplay book={book} large />

            <div className="promo-check-box">
              <label className="field-label">
                <span>Промокод</span>
                <input
                  value={promoCode}
                  onChange={(e) => {
                    setPromoCode(e.target.value);
                    setPricePreview(null);
                  }}
                  placeholder="Например: BIRTHDAY15"
                />
              </label>

              <button type="button" className="secondary" onClick={checkPromoCode}>
                Проверить промокод
              </button>

              {pricePreview?.PromoCodeAccepted && pricePreview?.AppliedPromoCode && (
                <p className="success promo-preview">
                  Применён промокод {pricePreview.AppliedPromoCode}: скидка {Number(pricePreview.DiscountPercent).toFixed(0)}%, итоговая цена {formatMoney(pricePreview.FinalPrice)}.
                </p>
              )}
            </div>

            <div className="actions">
              <label className="inline-label">
                UserId:
                <input
                  type="number"
                  value={userId}
                  onChange={(e) => setUserId(e.target.value)}
                  placeholder="UserId"
                />
              </label>

              <button onClick={buyBook}>Купить</button>

              <button onClick={addToFavorites}>В избранное</button>

              <Link className="button-link" to={`/reader/${book.BookId}?user_id=${userId}`}>
                Читать
              </Link>
            </div>

            {message && <p className="success">{message}</p>}
            {error && <p className="error">{error}</p>}
          </div>
        </div>
      </section>

      <section className="panel">
        <h2>Добавить отзыв</h2>

        <div className="review-form">
          <label className="field-label">
            <span>Оценка от 1 до 5</span>
            <input
              type="number"
              min="1"
              max="5"
              value={rating}
              onChange={(e) => setRating(e.target.value)}
            />
          </label>

          <label className="field-label">
            <span>Текст отзыва</span>
            <textarea
              value={reviewText}
              onChange={(e) => setReviewText(e.target.value)}
              placeholder="Текст отзыва"
            />
          </label>

          <button onClick={addReview}>Сохранить отзыв</button>
        </div>
      </section>

      <section className="panel">
        <h2>Отзывы</h2>

        {reviews.length === 0 && <p className="muted">Отзывов пока нет.</p>}

        {reviews.map((review) => (
          <div key={review.ReviewId} className="review">
            <strong>{review.Username}</strong>
            <span>★ {review.Rating}</span>
            <p>{review.ReviewText}</p>
          </div>
        ))}
      </section>
    </Layout>
  );
}

function LibraryPage() {
  const { userId } = useParams();
  const [library, setLibrary] = useState([]);
  const [error, setError] = useState("");

  async function loadLibrary() {
    try {
      setError("");
      const response = await api.get(`/users/${userId}/library`);
      setLibrary(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  useEffect(() => {
    loadLibrary();
  }, [userId]);

  return (
    <Layout>
      <section className="panel">
        <h1>Моя библиотека</h1>
        <p className="muted">Пользователь UserId = {userId}</p>

        {error && <p className="error">{error}</p>}

        {library.length === 0 && (
          <p className="muted">В библиотеке пока нет книг.</p>
        )}

        <div className="grid">
          {library.map((book) => (
            <article key={book.BookId} className="card">
              <BookCover title={book.Title} imageUrl={book.CoverImageUrl} />

              <div className="card-body">
                <h3>{book.Title}</h3>
                <p>{book.PublisherName}</p>
                <p className="badge">{book.AccessType}</p>
                <BookAccessBadge book={book} />

                <Link className="button-link" to={`/reader/${book.BookId}?user_id=${userId}`}>
                  Читать
                </Link>
              </div>
            </article>
          ))}
        </div>
      </section>
    </Layout>
  );
}

function ReaderPage() {
  const { bookId } = useParams();
  const query = new URLSearchParams(window.location.search);
  const initialUserId = Number(query.get("user_id")) || getCurrentUserId();

  const [userId, setUserId] = useState(initialUserId);
  const [content, setContent] = useState(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function loadContent() {
    try {
      setError("");
      const response = await api.get(`/books/${bookId}/content`, {
        params: { user_id: userId },
      });

      setContent(response.data);
      setCurrentPage(response.data?.CurrentPage || 1);
    } catch (err) {
      setContent(null);
      setError(err.response?.data?.detail || err.message);
    }
  }

  useEffect(() => {
    loadContent();
  }, [bookId]);

  async function saveProgress() {
    try {
      setMessage("");
      setError("");

      await api.put(`/books/${bookId}/progress`, {
        user_id: Number(userId),
        current_page: Number(currentPage),
      });

      setMessage("Прогресс чтения сохранён.");
      loadContent();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  return (
    <Layout>
      <section className="panel">
        <h1>Чтение книги</h1>

        <div className="actions">
          <label className="inline-label">
            UserId:
            <input
              type="number"
              value={userId}
              onChange={(e) => setUserId(e.target.value)}
            />
          </label>

          <button onClick={loadContent}>Открыть</button>
        </div>

        {error && <p className="error">{error}</p>}
        {message && <p className="success">{message}</p>}

        {content && (
          <>
            <h2>{content.Title}</h2>

            <div className="reader">
              {content.ContentText}
            </div>

            <div className="actions">
              <label className="inline-label">
                Страница:
                <input
                  type="number"
                  value={currentPage}
                  onChange={(e) => setCurrentPage(e.target.value)}
                />
              </label>

              <button onClick={saveProgress}>Сохранить прогресс</button>

              <span>
                Прогресс: {content.ProgressPercent ?? 0}%
              </span>
            </div>
          </>
        )}
      </section>
    </Layout>
  );
}

function FavoritesPage() {
  const { userId } = useParams();

  const [favorites, setFavorites] = useState([]);
  const [error, setError] = useState("");

  async function loadFavorites() {
    try {
      setError("");
      const response = await api.get(`/users/${userId}/favorites`);
      setFavorites(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  useEffect(() => {
    loadFavorites();
  }, [userId]);

  async function removeFromFavorites(bookId) {
    try {
      setError("");

      await api.delete(`/users/${Number(userId)}/favorites/${bookId}`);

      loadFavorites();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  return (
    <Layout>
      <section className="panel">
        <h1>Избранное</h1>
        <p className="muted">Пользователь UserId = {userId}</p>

        {error && <p className="error">{error}</p>}

        {favorites.length === 0 && (
          <p className="muted">В избранном пока нет книг.</p>
        )}

        <div className="grid">
          {favorites.map((book) => (
            <article key={book.BookId} className="card">
              <BookCover title={book.Title} imageUrl={book.CoverImageUrl} />

              <div className="card-body">
                <h3>{book.Title}</h3>
                <p>{book.PublisherName}</p>

                <PriceDisplay book={book} />

                <div className="actions">
                  <Link className="button-link" to={`/books/${book.BookId}`}>
                    Подробнее
                  </Link>

                  <button
                    className="secondary"
                    onClick={() => removeFromFavorites(book.BookId)}
                  >
                    Удалить
                  </button>
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>
    </Layout>
  );
}

function ProfilePage() {
  const { userId } = useParams();

  const [data, setData] = useState(null);
  const [topUpAmount, setTopUpAmount] = useState(500);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function loadProfile() {
    try {
      setError("");
      const response = await api.get(`/users/${userId}/profile`);
      setData(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  useEffect(() => {
    loadProfile();
  }, [userId]);

  async function topUpBalance() {
    try {
      setMessage("");
      setError("");

      const amount = Number(topUpAmount);

      if (!Number.isFinite(amount) || amount <= 0) {
        setError("Сумма пополнения должна быть больше нуля.");
        return;
      }

      const response = await api.post(`/users/${userId}/balance/top-up`, {
        amount,
        payment_method: "Card",
      });

      const newBalance = response.data?.Balance ?? response.data?.user?.Balance;

      setMessage(`Баланс успешно пополнен. Новый баланс: ${formatMoney(newBalance)}.`);

      const currentUser = getCurrentUser();
      if (currentUser && currentUser.UserId === Number(userId)) {
        saveCurrentUser({
          ...currentUser,
          Balance: newBalance,
        });
      }

      loadProfile();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  if (!data) {
    return (
      <Layout>
        <section className="panel">
          <h1>Профиль</h1>
          <p>Загрузка...</p>
          {error && <p className="error">{error}</p>}
        </section>
      </Layout>
    );
  }

  const profile = data.profile;
  const subscriptions = data.subscriptions || [];
  const payments = data.payments || [];
  const progress = data.reading_progress || [];

  return (
    <Layout>
      <section className="panel">
        <h1>Личный кабинет</h1>

        <div className="profile-box">
          <div>
            <h2>{profile.Username}</h2>
            <p className="muted">{profile.Email}</p>
            <p>Роль: {profile.RoleName}</p>
            <p>Дата рождения: {profile.DateOfBirth || "не указана"}</p>
            <p>Активен: {profile.IsActive ? "Да" : "Нет"}</p>

            {profile.HasBirthdayPromo && profile.BirthdayPromoCode && (
              <div className="birthday-promo-box">
                <strong>С днём рождения!</strong>
                <span>Ваш промокод на скидку 15% на любую книгу:</span>
                <code>{profile.BirthdayPromoCode}</code>
              </div>
            )}

            <div className="balance-box">
              <strong>{formatMoney(profile.Balance)}</strong>
              <span>текущий баланс</span>
            </div>
          </div>

          <div className="profile-stats">
            <div>
              <strong>{profile.PurchasedBookCount}</strong>
              <span>купленных книг</span>
            </div>

            <div>
              <strong>{profile.FavoriteBookCount}</strong>
              <span>в избранном</span>
            </div>
          </div>
        </div>
      </section>

      <section className="panel">
        <h2>Пополнение баланса</h2>
        <p className="muted">
          Введите положительную сумму. Пополнение создаёт запись в истории платежей.
        </p>

        <div className="actions">
          <label className="inline-label">
            Сумма:
            <input
              type="number"
              min="1"
              step="1"
              value={topUpAmount}
              onChange={(e) => setTopUpAmount(e.target.value)}
            />
          </label>

          <button type="button" onClick={topUpBalance}>
            Пополнить баланс
          </button>
        </div>

        {message && <p className="success">{message}</p>}
        {error && <p className="error">{error}</p>}
      </section>

      <section className="panel">
        <h2>Активные подписки</h2>

        {subscriptions.length === 0 && (
          <p className="muted">Активных подписок нет.</p>
        )}

        {subscriptions.map((sub) => (
          <div key={sub.SubscriptionId} className="table-card">
            <strong>{sub.PlanName}</strong>
            <span>{formatMoney(sub.Price)}</span>
            <span>{sub.StartDate} — {sub.EndDate}</span>
          </div>
        ))}
      </section>

      <section className="panel">
        <h2>Платежи</h2>

        {payments.length === 0 && (
          <p className="muted">Платежей пока нет.</p>
        )}

        {payments.map((payment) => (
          <div key={payment.PaymentId} className="table-card">
            <strong>{formatMoney(payment.Amount)}</strong>
            <span>{payment.PaymentMethod}</span>
            <span>{payment.PaymentStatus}</span>
            <span>{payment.TransactionNumber}</span>
          </div>
        ))}
      </section>

      <section className="panel">
        <h2>Прогресс чтения</h2>

        {progress.length === 0 && (
          <p className="muted">Прогресс чтения пока не сохранён.</p>
        )}

        {progress.map((item) => (
          <div key={item.ProgressId} className="table-card">
            <strong>{item.Title}</strong>
            <span>
              Страница {item.CurrentPage} из {item.PageCount}
            </span>
            <span>{item.ProgressPercent}%</span>
          </div>
        ))}
      </section>
    </Layout>
  );
}

function SubscriptionsPage() {
  const [plans, setPlans] = useState([]);
  const [userId, setUserId] = useState(getCurrentUserId());
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function loadPlans() {
    try {
      setError("");
      const response = await api.get("/subscriptions/plans");
      setPlans(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  useEffect(() => {
    loadPlans();
  }, []);

  async function createSubscription(planId) {
    try {
      setMessage("");
      setError("");

      const response = await api.post(`/users/${userId}/subscriptions`, {
        plan_id: planId,
        payment_method: "Balance",
      });

      const newBalance = response.data?.Balance ?? response.data?.subscription?.Balance;

      if (newBalance !== undefined && newBalance !== null) {
        setMessage(`Подписка оформлена. Остаток баланса: ${formatMoney(newBalance)}.`);
      } else {
        setMessage(`Подписка оформлена. SubscriptionId = ${response.data.SubscriptionId}`);
      }
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  return (
    <Layout>
      <section className="panel">
        <h1>Подписки</h1>
        <p className="muted">
          Подписка открывает доступ ко всем книгам, которые доступны по подписке.
        </p>

        <div className="actions">
          <label className="inline-label">
            UserId:
            <input
              type="number"
              value={userId}
              onChange={(e) => setUserId(e.target.value)}
            />
          </label>
        </div>

        {message && <p className="success">{message}</p>}
        {error && <p className="error">{error}</p>}

        <div className="grid">
          {plans.map((plan) => (
            <article key={plan.PlanId} className="card">
              <div className="card-body">
                <h3>{plan.PlanName}</h3>
                <p>{plan.Description}</p>

                <div className="meta">
                  <span>{plan.DurationDays} дней</span>
                  <span>{plan.Price} ₽</span>
                </div>

                <button onClick={() => createSubscription(plan.PlanId)}>
                  Оформить подписку
                </button>
              </div>
            </article>
          ))}
        </div>
      </section>
    </Layout>
  );
}

function AdminPage() {
  const currentUser = getCurrentUser();
  const isAdmin = isAdminUser(currentUser);

  const adminRequestConfig = {
    params: {
      admin_user_id: currentUser?.UserId,
    },
  };

  const adminTabs = [
    {
      id: "overview",
      label: "Обзор",
      description: "главные метрики",
    },
    {
      id: "books",
      label: "Книги",
      description: "каталог и справочники",
    },
    {
      id: "promotions",
      label: "Акции",
      description: "скидки и промокоды",
    },
    {
      id: "reports",
      label: "Отчёты",
      description: "аналитика БД",
    },
    {
      id: "sql",
      label: "SQL-объекты",
      description: "VIEW, PROCEDURE, FUNCTION, TRIGGER",
    },
    {
      id: "audit",
      label: "Журнал",
      description: "AuditLog",
    },
  ];

  const [activeAdminTab, setActiveAdminTab] = useState("overview");
  const [selectedSqlObject, setSelectedSqlObject] = useState(null);

  const [options, setOptions] = useState({
    publishers: [],
    authors: [],
    genres: [],
  });

  const [auditLog, setAuditLog] = useState([]);
  const [adminStats, setAdminStats] = useState(null);
  const [databaseDashboard, setDatabaseDashboard] = useState(null);
  const [promotions, setPromotions] = useState([]);
  const [promotionBooks, setPromotionBooks] = useState([]);
  const [promotionCatalogBooks, setPromotionCatalogBooks] = useState([]);
  const [promotionBookSearch, setPromotionBookSearch] = useState("");
  const [promotionForm, setPromotionForm] = useState({
    promotion_name: "",
    promo_code: "",
    discount_percent: 10,
    start_date: "2026-01-01",
    end_date: "2026-12-31",
    is_active: true,
    applies_to_all_books: false,
  });
  const [promotionAssignment, setPromotionAssignment] = useState({
    promotion_id: "",
    book_id: "",
  });

  const [salesReportFilters, setSalesReportFilters] = useState({
    start_date: "",
    end_date: "",
    group_by: "Book",
  });
  const [bookReportFilters, setBookReportFilters] = useState({
    genre_name: "",
    publisher_id: "",
    min_rating: "",
    only_with_discount: "",
    only_premium: "",
  });
  const [userReportFilters, setUserReportFilters] = useState({
    only_active: "",
    min_purchase_amount: "",
    registration_start: "",
    registration_end: "",
  });
  const [genreReportFilters, setGenreReportFilters] = useState({
    start_date: "",
    end_date: "",
  });
  const [auditReportFilters, setAuditReportFilters] = useState({
    table_name: "",
    action_name: "",
    start_date: "",
    end_date: "",
  });

  const [salesReport, setSalesReport] = useState({ group_by: "Book", rows: [] });
  const [bookReport, setBookReport] = useState([]);
  const [userReport, setUserReport] = useState([]);
  const [genreReport, setGenreReport] = useState([]);
  const [auditReport, setAuditReport] = useState([]);
  const [reportLoading, setReportLoading] = useState(false);

  const [publisherSearch, setPublisherSearch] = useState("");
  const [authorSearch, setAuthorSearch] = useState("");
  const [genreSearch, setGenreSearch] = useState("");

  const [newPublisherName, setNewPublisherName] = useState("");
  const [newAuthorFirstName, setNewAuthorFirstName] = useState("");
  const [newAuthorLastName, setNewAuthorLastName] = useState("");
  const [newGenreName, setNewGenreName] = useState("");

  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [textFileName, setTextFileName] = useState("");

  const [form, setForm] = useState({
    publisher_id: "",
    author_ids: [],
    genre_ids: [],
    title: "",
    description: "",
    publication_year: 2026,
    age_limit: 12,
    page_count: 100,
    price: 199,
    is_free: false,
    is_premium: false,
    is_available_by_subscription: true,
    cover_image_url: "",
    content_text: "Тестовый текст новой цифровой книги.",
    content_format: "TEXT",
  });

  const filteredPublishers = options.publishers.filter((publisher) =>
    publisher.PublisherName.toLowerCase().includes(publisherSearch.toLowerCase())
  );

  const filteredAuthors = options.authors.filter((author) =>
    author.AuthorName.toLowerCase().includes(authorSearch.toLowerCase())
  );

  const filteredGenres = options.genres.filter((genre) =>
    genre.GenreName.toLowerCase().includes(genreSearch.toLowerCase())
  );

  const selectedPublisher = options.publishers.find(
    (publisher) => publisher.PublisherId === Number(form.publisher_id)
  );

  const selectedAuthors = options.authors.filter((author) =>
    form.author_ids.includes(author.AuthorId)
  );

  const selectedGenres = options.genres.filter((genre) =>
    form.genre_ids.includes(genre.GenreId)
  );

  const filteredPromotionBooks = promotionCatalogBooks.filter((book) => {
    const searchText = promotionBookSearch.toLowerCase();

    if (!searchText) {
      return true;
    }

    return String(book.Title || "").toLowerCase().includes(searchText);
  });

  const sqlObjectGroups = groupSqlObjects(databaseDashboard?.sql_objects || []);

  async function loadOptions() {
    if (!isAdmin) {
      return;
    }

    try {
      const response = await api.get("/admin/options", adminRequestConfig);
      setOptions(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function loadAuditLog() {
    if (!isAdmin) {
      return;
    }

    try {
      const response = await api.get("/admin/audit-log", adminRequestConfig);
      setAuditLog(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function loadAdminStats() {
    if (!isAdmin) {
      return;
    }

    try {
      const response = await api.get("/admin/stats", adminRequestConfig);
      setAdminStats(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function loadDatabaseDashboard() {
    if (!isAdmin) {
      return;
    }

    try {
      const response = await api.get("/admin/database-dashboard", adminRequestConfig);
      setDatabaseDashboard(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function loadPromotions() {
    if (!isAdmin) {
      return;
    }

    try {
      const response = await api.get("/admin/promotions", adminRequestConfig);
      setPromotions(response.data.promotions || []);
      setPromotionBooks(response.data.promotion_books || []);
      setPromotionCatalogBooks(response.data.books || []);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  useEffect(() => {
    if (isAdmin) {
      loadOptions();
      loadAuditLog();
      loadAdminStats();
      loadDatabaseDashboard();
      loadPromotions();
      loadSalesReport();
      loadBookReport();
      loadUserReport();
      loadGenreReport();
      loadAuditReport();
    }
  }, [isAdmin]);

  function updateField(field, value) {
    setForm((oldForm) => ({
      ...oldForm,
      [field]: value,
    }));
  }

  function toggleId(field, id) {
    setForm((oldForm) => {
      const currentValues = oldForm[field];

      if (currentValues.includes(id)) {
        return {
          ...oldForm,
          [field]: currentValues.filter((value) => value !== id),
        };
      }

      return {
        ...oldForm,
        [field]: [...currentValues, id],
      };
    });
  }

  async function handleBookTextFile(event) {
    try {
      setMessage("");
      setError("");

      const file = event.target.files?.[0];

      if (!file) {
        return;
      }

      const isTxtFile =
        file.type === "text/plain" ||
        file.name.toLowerCase().endsWith(".txt");

      if (!isTxtFile) {
        setError("Можно загрузить только .txt-файл с текстом книги.");
        event.target.value = "";
        return;
      }

      const maxSizeBytes = 2 * 1024 * 1024;

      if (file.size > maxSizeBytes) {
        setError("Файл слишком большой. Максимальный размер: 2 МБ.");
        event.target.value = "";
        return;
      }

      const text = await file.text();

      if (!text.trim()) {
        setError("Файл пустой. Выберите .txt-файл с текстом книги.");
        event.target.value = "";
        return;
      }

      updateField("content_text", text);
      setTextFileName(file.name);
      setMessage(`Текст книги загружен из файла: ${file.name}`);

      event.target.value = "";
    } catch {
      setError("Не удалось прочитать файл. Сохраните файл в кодировке UTF-8 и попробуйте снова.");
      event.target.value = "";
    }
  }

  async function createPublisher() {
    try {
      setMessage("");
      setError("");

      const publisherName = newPublisherName.trim();

      if (!publisherName) {
        setError("Введите название издательства.");
        return;
      }

      const response = await api.post(
        "/admin/publishers",
        {
          publisher_name: publisherName,
        },
        adminRequestConfig
      );

      const createdPublisher = response.data;

      setOptions((oldOptions) => ({
        ...oldOptions,
        publishers: [
          ...oldOptions.publishers.filter(
            (publisher) => publisher.PublisherId !== createdPublisher.PublisherId
          ),
          createdPublisher,
        ].sort((a, b) => a.PublisherName.localeCompare(b.PublisherName)),
      }));

      updateField("publisher_id", createdPublisher.PublisherId);
      setPublisherSearch(createdPublisher.PublisherName);
      setNewPublisherName("");
      setMessage(`Издательство добавлено и выбрано: ${createdPublisher.PublisherName}`);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function createAuthor() {
    try {
      setMessage("");
      setError("");

      const firstName = newAuthorFirstName.trim();
      const lastName = newAuthorLastName.trim();

      if (!firstName || !lastName) {
        setError("Введите имя и фамилию автора.");
        return;
      }

      const response = await api.post(
        "/admin/authors",
        {
          first_name: firstName,
          last_name: lastName,
        },
        adminRequestConfig
      );

      const createdAuthor = response.data;

      setOptions((oldOptions) => ({
        ...oldOptions,
        authors: [
          ...oldOptions.authors.filter(
            (author) => author.AuthorId !== createdAuthor.AuthorId
          ),
          createdAuthor,
        ].sort((a, b) => a.AuthorName.localeCompare(b.AuthorName)),
      }));

      setForm((oldForm) => ({
        ...oldForm,
        author_ids: oldForm.author_ids.includes(createdAuthor.AuthorId)
          ? oldForm.author_ids
          : [...oldForm.author_ids, createdAuthor.AuthorId],
      }));

      setAuthorSearch(createdAuthor.AuthorName);
      setNewAuthorFirstName("");
      setNewAuthorLastName("");
      setMessage(`Автор добавлен и выбран: ${createdAuthor.AuthorName}`);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function createGenre() {
    try {
      setMessage("");
      setError("");

      const genreName = newGenreName.trim();

      if (!genreName) {
        setError("Введите название жанра.");
        return;
      }

      const response = await api.post(
        "/admin/genres",
        {
          genre_name: genreName,
        },
        adminRequestConfig
      );

      const createdGenre = response.data;

      setOptions((oldOptions) => ({
        ...oldOptions,
        genres: [
          ...oldOptions.genres.filter(
            (genre) => genre.GenreId !== createdGenre.GenreId
          ),
          createdGenre,
        ].sort((a, b) => a.GenreName.localeCompare(b.GenreName)),
      }));

      setForm((oldForm) => ({
        ...oldForm,
        genre_ids: oldForm.genre_ids.includes(createdGenre.GenreId)
          ? oldForm.genre_ids
          : [...oldForm.genre_ids, createdGenre.GenreId],
      }));

      setGenreSearch(createdGenre.GenreName);
      setNewGenreName("");
      setMessage(`Жанр добавлен и выбран: ${createdGenre.GenreName}`);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  function updatePromotionField(field, value) {
    setPromotionForm((oldForm) => ({
      ...oldForm,
      [field]: value,
    }));
  }

  async function createPromotion() {
    try {
      setMessage("");
      setError("");

      const promotionName = promotionForm.promotion_name.trim();
      const promoCode = promotionForm.promo_code.trim().toUpperCase();
      const discountPercent = Number(promotionForm.discount_percent);

      if (!promotionName) {
        setError("Введите название акции.");
        return;
      }

      if (!promoCode) {
        setError("Введите промокод.");
        return;
      }

      if (!Number.isFinite(discountPercent) || discountPercent <= 0 || discountPercent > 100) {
        setError("Скидка должна быть больше 0 и не больше 100%.");
        return;
      }

      if (!promotionForm.start_date || !promotionForm.end_date) {
        setError("Укажите даты начала и окончания акции.");
        return;
      }

      const response = await api.post(
        "/admin/promotions",
        {
          promotion_name: promotionName,
          promo_code: promoCode,
          discount_percent: discountPercent,
          start_date: promotionForm.start_date,
          end_date: promotionForm.end_date,
          is_active: promotionForm.is_active,
          applies_to_all_books: promotionForm.applies_to_all_books,
        },
        adminRequestConfig
      );

      const createdPromotion = response.data;

      setPromotionAssignment((oldValue) => ({
        ...oldValue,
        promotion_id: createdPromotion.PromotionId,
      }));

      setPromotionForm({
        promotion_name: "",
        promo_code: "",
        discount_percent: 10,
        start_date: "2026-01-01",
        end_date: "2026-12-31",
        is_active: true,
        applies_to_all_books: false,
      });

      setMessage(`Акция сохранена: ${createdPromotion.PromotionName}`);
      loadPromotions();
      loadDatabaseDashboard();
      loadAuditLog();
      loadAdminStats();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function assignPromotionToBook() {
    try {
      setMessage("");
      setError("");

      const promotionId = Number(promotionAssignment.promotion_id);
      const bookId = Number(promotionAssignment.book_id);

      if (!promotionId) {
        setError("Выберите акцию.");
        return;
      }

      if (!bookId) {
        setError("Выберите книгу для акции.");
        return;
      }

      await api.post(
        `/admin/promotions/${promotionId}/books/${bookId}`,
        null,
        adminRequestConfig
      );

      setMessage("Книга добавлена в акцию.");
      loadPromotions();
      loadDatabaseDashboard();
      loadAuditLog();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function removePromotionFromBook(promotionId, bookId) {
    try {
      setMessage("");
      setError("");

      await api.delete(
        `/admin/promotions/${promotionId}/books/${bookId}`,
        adminRequestConfig
      );

      setMessage("Книга удалена из акции.");
      loadPromotions();
      loadDatabaseDashboard();
      loadAuditLog();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  async function deletePromotion(promotion) {
    const promotionName = promotion?.PromotionName || "выбранную акцию";

    if (!window.confirm(`Удалить акцию «${promotionName}»? Все привязки книг к этой акции тоже будут удалены.`)) {
      return;
    }

    try {
      setMessage("");
      setError("");

      await api.delete(
        `/admin/promotions/${promotion.PromotionId}`,
        adminRequestConfig
      );

      setMessage(`Акция удалена: ${promotionName}`);

      setPromotionAssignment((oldValue) => ({
        ...oldValue,
        promotion_id:
          Number(oldValue.promotion_id) === promotion.PromotionId
            ? ""
            : oldValue.promotion_id,
      }));

      loadPromotions();
      loadDatabaseDashboard();
      loadAuditLog();
      loadAdminStats();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  function valueOrUndefined(value) {
    if (value === "" || value === null || value === undefined) {
      return undefined;
    }

    return value;
  }

  function updateSalesReportFilter(field, value) {
    setSalesReportFilters((oldFilters) => ({
      ...oldFilters,
      [field]: value,
    }));
  }

  function updateBookReportFilter(field, value) {
    setBookReportFilters((oldFilters) => ({
      ...oldFilters,
      [field]: value,
    }));
  }

  function updateUserReportFilter(field, value) {
    setUserReportFilters((oldFilters) => ({
      ...oldFilters,
      [field]: value,
    }));
  }

  function updateGenreReportFilter(field, value) {
    setGenreReportFilters((oldFilters) => ({
      ...oldFilters,
      [field]: value,
    }));
  }

  function updateAuditReportFilter(field, value) {
    setAuditReportFilters((oldFilters) => ({
      ...oldFilters,
      [field]: value,
    }));
  }

  async function loadSalesReport() {
    try {
      setReportLoading(true);
      setError("");

      const response = await api.get("/admin/reports/sales", {
        params: {
          admin_user_id: currentUser?.UserId,
          start_date: valueOrUndefined(salesReportFilters.start_date),
          end_date: valueOrUndefined(salesReportFilters.end_date),
          group_by: salesReportFilters.group_by,
        },
      });

      setSalesReport(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    } finally {
      setReportLoading(false);
    }
  }

  async function loadBookReport() {
    try {
      setReportLoading(true);
      setError("");

      const response = await api.get("/admin/reports/books", {
        params: {
          admin_user_id: currentUser?.UserId,
          genre_name: valueOrUndefined(bookReportFilters.genre_name),
          publisher_id: valueOrUndefined(bookReportFilters.publisher_id),
          min_rating: valueOrUndefined(bookReportFilters.min_rating),
          only_with_discount: valueOrUndefined(bookReportFilters.only_with_discount),
          only_premium: valueOrUndefined(bookReportFilters.only_premium),
        },
      });

      setBookReport(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    } finally {
      setReportLoading(false);
    }
  }

  async function loadUserReport() {
    try {
      setReportLoading(true);
      setError("");

      const response = await api.get("/admin/reports/users", {
        params: {
          admin_user_id: currentUser?.UserId,
          only_active: valueOrUndefined(userReportFilters.only_active),
          min_purchase_amount: valueOrUndefined(userReportFilters.min_purchase_amount),
          registration_start: valueOrUndefined(userReportFilters.registration_start),
          registration_end: valueOrUndefined(userReportFilters.registration_end),
        },
      });

      setUserReport(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    } finally {
      setReportLoading(false);
    }
  }

  async function loadGenreReport() {
    try {
      setReportLoading(true);
      setError("");

      const response = await api.get("/admin/reports/genres", {
        params: {
          admin_user_id: currentUser?.UserId,
          start_date: valueOrUndefined(genreReportFilters.start_date),
          end_date: valueOrUndefined(genreReportFilters.end_date),
        },
      });

      setGenreReport(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    } finally {
      setReportLoading(false);
    }
  }

  async function loadAuditReport() {
    try {
      setReportLoading(true);
      setError("");

      const response = await api.get("/admin/reports/audit-log", {
        params: {
          admin_user_id: currentUser?.UserId,
          table_name: valueOrUndefined(auditReportFilters.table_name),
          action_name: valueOrUndefined(auditReportFilters.action_name),
          start_date: valueOrUndefined(auditReportFilters.start_date),
          end_date: valueOrUndefined(auditReportFilters.end_date),
        },
      });

      setAuditReport(response.data);
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    } finally {
      setReportLoading(false);
    }
  }

  async function loadAllInteractiveReports() {
    await loadSalesReport();
    await loadBookReport();
    await loadUserReport();
    await loadGenreReport();
    await loadAuditReport();
  }

  async function createBook() {
    try {
      setMessage("");
      setError("");

      if (!form.publisher_id) {
        setError("Выберите издательство.");
        return;
      }

      if (form.author_ids.length === 0) {
        setError("Выберите хотя бы одного автора.");
        return;
      }

      if (form.genre_ids.length === 0) {
        setError("Выберите хотя бы один жанр.");
        return;
      }

      if (!form.title.trim()) {
        setError("Введите название книги.");
        return;
      }

      if (!form.content_text.trim()) {
        setError("Добавьте текст книги вручную или загрузите .txt-файл.");
        return;
      }

      const payload = {
        ...form,
        publisher_id: Number(form.publisher_id),
        author_ids: form.author_ids.map(Number),
        genre_ids: form.genre_ids.map(Number),
        publication_year: Number(form.publication_year),
        age_limit: Number(form.age_limit),
        page_count: Number(form.page_count),
        price: Number(form.price),
        title: form.title.trim(),
        description: form.description.trim() || null,
        cover_image_url: form.cover_image_url.trim() || null,
      };

      const response = await api.post("/admin/books", payload, adminRequestConfig);

      setMessage(`Книга создана: ${response.data.Title || response.data.message}`);

      setForm((oldForm) => ({
        ...oldForm,
        title: "",
        description: "",
        content_text: "Тестовый текст новой цифровой книги.",
        cover_image_url: "",
      }));

      setTextFileName("");

      loadAuditLog();
      loadAdminStats();
      loadDatabaseDashboard();
      loadPromotions();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  if (!isAdmin) {
    return (
      <Layout>
        <section className="panel">
          <h1>Доступ запрещён</h1>
          <p className="muted">
            Админ-панель доступна только пользователю с ролью администратора.
          </p>

          <Link className="button-link" to="/login">
            Войти как администратор
          </Link>
        </section>
      </Layout>
    );
  }

  return (
    <Layout>
      <section className="panel admin-shell-panel">
        <div className="section-heading admin-main-heading">
          <div>
            <h1>Админ-панель</h1>
            <p className="muted">
              Управление книгами, акциями, отчётами, SQL-объектами и журналом действий базы данных.
            </p>
          </div>

          <button
            type="button"
            className="secondary"
            onClick={() => {
              loadOptions();
              loadAuditLog();
              loadAdminStats();
              loadDatabaseDashboard();
              loadPromotions();
            }}
          >
            Обновить данные
          </button>
        </div>

        {message && <p className="success">{message}</p>}
        {error && <p className="error">{error}</p>}

        <div className="admin-tabs" role="tablist" aria-label="Разделы админ-панели">
          {adminTabs.map((tab) => (
            <button
              key={tab.id}
              type="button"
              className={activeAdminTab === tab.id ? "admin-tab active" : "admin-tab"}
              onClick={() => setActiveAdminTab(tab.id)}
            >
              <strong>{tab.label}</strong>
              <span>{tab.description}</span>
            </button>
          ))}
        </div>
      </section>

      {activeAdminTab === "overview" && (
        <section className="panel admin-tab-panel">
          <div className="section-heading">
            <div>
              <h2>Обзор проекта</h2>
              <p className="muted">
                Короткая сводка по основным сущностям БД и быстрый переход к рабочим разделам.
              </p>
            </div>
          </div>

          {adminStats && (
            <div className="stats-grid">
              <div className="stat-card">
                <strong>{adminStats.stats.BookCount}</strong>
                <span>книг</span>
              </div>

              <div className="stat-card">
                <strong>{adminStats.stats.UserCount}</strong>
                <span>пользователей</span>
              </div>

              <div className="stat-card">
                <strong>{adminStats.stats.PurchaseCount}</strong>
                <span>покупок</span>
              </div>

              <div className="stat-card">
                <strong>{formatMoney(adminStats.stats.TotalSales)}</strong>
                <span>сумма продаж</span>
              </div>

              <div className="stat-card">
                <strong>{adminStats.stats.PromotionCount ?? 0}</strong>
                <span>акций</span>
              </div>

              <div className="stat-card">
                <strong>{adminStats.stats.ActivePromotionCount ?? 0}</strong>
                <span>активных акций</span>
              </div>
            </div>
          )}

          {databaseDashboard && (
            <div className="admin-overview-grid">
              <button type="button" className="admin-overview-card" onClick={() => setActiveAdminTab("books")}>
                <strong>{databaseDashboard.metrics.AuthorCount}</strong>
                <span>авторов в справочнике</span>
              </button>

              <button type="button" className="admin-overview-card" onClick={() => setActiveAdminTab("books")}>
                <strong>{databaseDashboard.metrics.GenreCount}</strong>
                <span>жанров в справочнике</span>
              </button>

              <button type="button" className="admin-overview-card" onClick={() => setActiveAdminTab("reports")}>
                <strong>{databaseDashboard.metrics.PaymentCount}</strong>
                <span>платежей в БД</span>
              </button>

              <button type="button" className="admin-overview-card" onClick={() => setActiveAdminTab("audit")}>
                <strong>{databaseDashboard.metrics.AuditLogCount}</strong>
                <span>записей AuditLog</span>
              </button>
            </div>
          )}

          {adminStats?.popular_books?.length > 0 && (
            <div className="report-box">
              <h3>Популярные книги</h3>
              <div className="compact-report-list">
                {adminStats.popular_books.map((book) => (
                  <div key={book.BookId} className="report-row compact">
                    <strong>{book.Title}</strong>
                    <span>покупок: {book.PurchaseCount} · избранное: {book.FavoriteCount} · отзывов: {book.ReviewCount}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </section>
      )}

      {activeAdminTab === "books" && (
        <section className="panel admin-tab-panel">
          <div className="section-heading">
            <div>
              <h2>Книги и справочники</h2>
              <p className="muted">
                Добавление книги, выбор издательства, авторов, жанров и загрузка текста из TXT-файла.
              </p>
            </div>
          </div>

        <div className="admin-form">
          <label className="field-label">
            <span>Название книги</span>
            <input
              value={form.title}
              onChange={(e) => updateField("title", e.target.value)}
              placeholder="Например: Пикник на обочине"
            />
          </label>

          <label className="field-label">
            <span>Описание книги</span>
            <textarea
              value={form.description}
              onChange={(e) => updateField("description", e.target.value)}
              placeholder="Краткое описание книги"
            />
          </label>

          <div className="admin-section">
            <h2>Издательство</h2>

            <label className="field-label">
              <span>Поиск издательства</span>
              <input
                value={publisherSearch}
                onChange={(e) => setPublisherSearch(e.target.value)}
                placeholder="Введите название издательства"
              />
            </label>

            {selectedPublisher && (
              <p className="selected-info">
                Выбрано: <strong>{selectedPublisher.PublisherName}</strong>
              </p>
            )}

            <div className="option-list">
              {filteredPublishers.map((publisher) => (
                <button
                  key={publisher.PublisherId}
                  type="button"
                  className={
                    Number(form.publisher_id) === publisher.PublisherId
                      ? "option-button active"
                      : "option-button"
                  }
                  onClick={() => updateField("publisher_id", publisher.PublisherId)}
                >
                  {publisher.PublisherName}
                </button>
              ))}
            </div>

            <div className="entity-box">
              <h3>Добавить новое издательство</h3>

              <div className="entity-grid">
                <label className="field-label">
                  <span>Название издательства</span>
                  <input
                    value={newPublisherName}
                    onChange={(e) => setNewPublisherName(e.target.value)}
                    placeholder="Например: АСТ"
                  />
                </label>
              </div>

              <button type="button" onClick={createPublisher}>
                Добавить и выбрать издательство
              </button>
            </div>
          </div>

          <div className="admin-section">
            <h2>Авторы</h2>

            <label className="field-label">
              <span>Поиск автора</span>
              <input
                value={authorSearch}
                onChange={(e) => setAuthorSearch(e.target.value)}
                placeholder="Введите имя или фамилию автора"
              />
            </label>

            {selectedAuthors.length > 0 && (
              <div className="selected-row">
                {selectedAuthors.map((author) => (
                  <button
                    key={author.AuthorId}
                    type="button"
                    className="pill selected"
                    onClick={() => toggleId("author_ids", author.AuthorId)}
                  >
                    {author.AuthorName} ×
                  </button>
                ))}
              </div>
            )}

            <div className="checkbox-list">
              {filteredAuthors.map((author) => (
                <label key={author.AuthorId} className="option-checkbox">
                  <input
                    type="checkbox"
                    checked={form.author_ids.includes(author.AuthorId)}
                    onChange={() => toggleId("author_ids", author.AuthorId)}
                  />
                  {author.AuthorName}
                </label>
              ))}
            </div>

            <div className="entity-box">
              <h3>Добавить нового автора</h3>

              <div className="entity-grid two-columns">
                <label className="field-label">
                  <span>Имя</span>
                  <input
                    value={newAuthorFirstName}
                    onChange={(e) => setNewAuthorFirstName(e.target.value)}
                    placeholder="Имя"
                  />
                </label>

                <label className="field-label">
                  <span>Фамилия</span>
                  <input
                    value={newAuthorLastName}
                    onChange={(e) => setNewAuthorLastName(e.target.value)}
                    placeholder="Фамилия"
                  />
                </label>
              </div>

              <button type="button" onClick={createAuthor}>
                Добавить и выбрать автора
              </button>
            </div>
          </div>

          <div className="admin-section">
            <h2>Жанры</h2>

            <label className="field-label">
              <span>Поиск жанра</span>
              <input
                value={genreSearch}
                onChange={(e) => setGenreSearch(e.target.value)}
                placeholder="Введите название жанра"
              />
            </label>

            {selectedGenres.length > 0 && (
              <div className="selected-row">
                {selectedGenres.map((genre) => (
                  <button
                    key={genre.GenreId}
                    type="button"
                    className="pill selected"
                    onClick={() => toggleId("genre_ids", genre.GenreId)}
                  >
                    {genre.GenreName} ×
                  </button>
                ))}
              </div>
            )}

            <div className="checkbox-list">
              {filteredGenres.map((genre) => (
                <label key={genre.GenreId} className="option-checkbox">
                  <input
                    type="checkbox"
                    checked={form.genre_ids.includes(genre.GenreId)}
                    onChange={() => toggleId("genre_ids", genre.GenreId)}
                  />
                  {genre.GenreName}
                </label>
              ))}
            </div>

            <div className="entity-box">
              <h3>Добавить новый жанр</h3>

              <div className="entity-grid">
                <label className="field-label">
                  <span>Название жанра</span>
                  <input
                    value={newGenreName}
                    onChange={(e) => setNewGenreName(e.target.value)}
                    placeholder="Например: Постапокалипсис"
                  />
                </label>
              </div>

              <button type="button" onClick={createGenre}>
                Добавить и выбрать жанр
              </button>
            </div>
          </div>

          <div className="admin-row">
            <label className="field-label">
              <span>Год публикации</span>
              <input
                type="number"
                value={form.publication_year}
                onChange={(e) => updateField("publication_year", e.target.value)}
              />
            </label>

            <label className="field-label">
              <span>Возрастное ограничение</span>
              <input
                type="number"
                value={form.age_limit}
                onChange={(e) => updateField("age_limit", e.target.value)}
              />
            </label>

            <label className="field-label">
              <span>Количество страниц</span>
              <input
                type="number"
                value={form.page_count}
                onChange={(e) => updateField("page_count", e.target.value)}
              />
            </label>

            <label className="field-label">
              <span>Цена</span>
              <input
                type="number"
                disabled={form.is_free}
                value={form.price}
                onChange={(e) => updateField("price", e.target.value)}
              />
            </label>
          </div>

          <label className="field-label">
            <span>Ссылка на изображение книги</span>
            <input
              value={form.cover_image_url}
              onChange={(e) => updateField("cover_image_url", e.target.value)}
              placeholder="/covers/book.jpg или URL картинки"
            />
          </label>

          <label className="checkbox">
            <input
              type="checkbox"
              checked={form.is_free}
              onChange={(e) => {
                updateField("is_free", e.target.checked);

                if (e.target.checked) {
                  updateField("price", 0);
                  updateField("is_premium", false);
                }
              }}
            />
            Бесплатная книга
          </label>

          <label className="checkbox">
            <input
              type="checkbox"
              checked={form.is_premium}
              onChange={(e) => {
                updateField("is_premium", e.target.checked);

                if (e.target.checked) {
                  updateField("is_free", false);
                  updateField("is_available_by_subscription", false);
                }
              }}
            />
            Премиальная книга: доступна только после покупки
          </label>

          <label className="checkbox">
            <input
              type="checkbox"
              disabled={form.is_premium}
              checked={form.is_available_by_subscription}
              onChange={(e) =>
                updateField("is_available_by_subscription", e.target.checked)
              }
            />
            Доступна по подписке
          </label>

          <div className="book-text-loader">
            <div>
              <h3>Текст книги</h3>
              <p className="muted">
                Можно вставить текст вручную или загрузить .txt-файл. Содержимое файла автоматически попадёт в поле ниже.
              </p>
            </div>

            <label className="file-upload-box">
              <span>Загрузить TXT-файл</span>
              <input
                type="file"
                accept=".txt,text/plain"
                onChange={handleBookTextFile}
              />
            </label>

            {textFileName && (
              <p className="file-name">
                Загружен файл: <strong>{textFileName}</strong>
              </p>
            )}

            <label className="field-label">
              <span>Текст книги</span>
              <textarea
                value={form.content_text}
                onChange={(e) => {
                  updateField("content_text", e.target.value);

                  if (textFileName) {
                    setTextFileName("");
                  }
                }}
                placeholder="Текст цифровой книги"
              />
            </label>
          </div>

          <button type="button" onClick={createBook}>
            Добавить книгу
          </button>
        </div>
        </section>
      )}

      {activeAdminTab === "promotions" && (
      <section className="panel">
        <h2>Акции и скидки</h2>
        <p className="muted">
          Здесь администратор управляет сущностями Promotion и BookPromotion из базы данных.
          Активная скидка автоматически отображается в каталоге и применяется при покупке.
        </p>

        <div className="promotion-admin-grid">
          <div className="entity-box">
            <h3>Создать или обновить акцию</h3>

            <div className="entity-grid two-columns">
              <label className="field-label">
                <span>Название акции</span>
                <input
                  value={promotionForm.promotion_name}
                  onChange={(e) => updatePromotionField("promotion_name", e.target.value)}
                  placeholder="Например: Скидка на классику"
                />
              </label>

              <label className="field-label">
                <span>Промокод</span>
                <input
                  value={promotionForm.promo_code}
                  onChange={(e) => updatePromotionField("promo_code", e.target.value)}
                  placeholder="Например: CLASSIC15"
                />
              </label>

              <label className="field-label">
                <span>Скидка, %</span>
                <input
                  type="number"
                  min="1"
                  max="100"
                  step="1"
                  value={promotionForm.discount_percent}
                  onChange={(e) => updatePromotionField("discount_percent", e.target.value)}
                />
              </label>

              <label className="field-label">
                <span>Активна</span>
                <select
                  value={promotionForm.is_active ? "1" : "0"}
                  onChange={(e) => updatePromotionField("is_active", e.target.value === "1")}
                >
                  <option value="1">Да</option>
                  <option value="0">Нет</option>
                </select>
              </label>

              <label className="checkbox promotion-global-checkbox">
                <input
                  type="checkbox"
                  checked={promotionForm.applies_to_all_books}
                  onChange={(e) => updatePromotionField("applies_to_all_books", e.target.checked)}
                />
                Действует на все книги
              </label>

              <label className="field-label">
                <span>Дата начала</span>
                <input
                  type="date"
                  value={promotionForm.start_date}
                  onChange={(e) => updatePromotionField("start_date", e.target.value)}
                />
              </label>

              <label className="field-label">
                <span>Дата окончания</span>
                <input
                  type="date"
                  value={promotionForm.end_date}
                  onChange={(e) => updatePromotionField("end_date", e.target.value)}
                />
              </label>
            </div>

            <button type="button" onClick={createPromotion}>
              Сохранить акцию
            </button>
          </div>

          <div className="entity-box">
            <h3>Привязать книгу к акции</h3>

            <label className="field-label">
              <span>Акция</span>
              <select
                value={promotionAssignment.promotion_id}
                onChange={(e) =>
                  setPromotionAssignment({
                    ...promotionAssignment,
                    promotion_id: e.target.value,
                  })
                }
              >
                <option value="">Выберите акцию</option>
                {promotions.filter((promotion) => !promotion.AppliesToAllBooks).map((promotion) => (
                  <option key={promotion.PromotionId} value={promotion.PromotionId}>
                    {promotion.PromotionName} — {Number(promotion.DiscountPercent).toFixed(0)}%
                  </option>
                ))}
              </select>
            </label>

            <label className="field-label">
              <span>Поиск книги</span>
              <input
                value={promotionBookSearch}
                onChange={(e) => setPromotionBookSearch(e.target.value)}
                placeholder="Введите название книги"
              />
            </label>

            <div className="option-list promotion-book-list">
              {filteredPromotionBooks.map((book) => (
                <button
                  key={book.BookId}
                  type="button"
                  className={
                    Number(promotionAssignment.book_id) === book.BookId
                      ? "option-button active"
                      : "option-button"
                  }
                  onClick={() =>
                    setPromotionAssignment({
                      ...promotionAssignment,
                      book_id: book.BookId,
                    })
                  }
                >
                  {book.Title} — {formatMoney(book.Price)}
                </button>
              ))}
            </div>

            <button type="button" onClick={assignPromotionToBook}>
              Добавить книгу в акцию
            </button>
          </div>
        </div>

        <h3>Список акций</h3>

        {promotions.length === 0 && (
          <p className="muted">Акций пока нет.</p>
        )}

        <div className="promotion-list">
          {promotions.map((promotion) => {
            const linkedBooks = promotionBooks.filter(
              (item) => item.PromotionId === promotion.PromotionId
            );

            return (
              <div key={promotion.PromotionId} className="promotion-card">
                <div className="promotion-card-header">
                  <div>
                    <h3>{promotion.PromotionName}</h3>
                    <p className="muted">
                      Промокод: <strong>{promotion.PromoCode}</strong>
                    </p>
                  </div>

                  <div className="promotion-card-actions">
                    <div className="discount-badge promotion-discount">
                      −{Number(promotion.DiscountPercent).toFixed(0)}%
                    </div>

                    <button
                      type="button"
                      className="danger-button small-button"
                      disabled={promotion.IsSystem}
                      onClick={() => deletePromotion(promotion)}
                    >
                      {promotion.IsSystem ? "Системная акция" : "Удалить акцию"}
                    </button>
                  </div>
                </div>

                <div className="details-meta">
                  <span>Начало: {promotion.StartDate}</span>
                  <span>Окончание: {promotion.EndDate}</span>
                  <span>{promotion.IsActive ? "Активна" : "Отключена"}</span>
                  <span>{promotion.AppliesToAllBooks ? "Действует на все книги" : `Книг: ${promotion.BookCount}`}</span>
                  {promotion.RequiresBirthday && <span>Только в день рождения пользователя</span>}
                  {promotion.IsSystem && <span>Системная акция</span>}
                </div>

                {linkedBooks.length > 0 ? (
                  <div className="promotion-linked-books">
                    {linkedBooks.map((book) => (
                      <div key={`${promotion.PromotionId}-${book.BookId}`} className="promotion-linked-book">
                        <div>
                          <strong>{book.Title}</strong>
                          <p className="muted">
                            {formatMoney(book.Price)} → {formatMoney(book.FinalPrice)}
                          </p>
                        </div>

                        <button
                          type="button"
                          className="secondary small-button"
                          onClick={() => removePromotionFromBook(promotion.PromotionId, book.BookId)}
                        >
                          Убрать
                        </button>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="muted">Книги к акции пока не привязаны.</p>
                )}
              </div>
            );
          })}
        </div>
      </section>
      )}

      {activeAdminTab === "reports" && (
        <section className="panel database-dashboard-panel admin-tab-panel">
          <div className="section-heading">
            <div>
              <h2>Отчёты с фильтрами</h2>
              <p className="muted">
                Здесь администратор сам задаёт параметры, а backend вызывает специализированные SQL-процедуры отчётности.
              </p>
            </div>

            <button type="button" className="secondary" onClick={loadAllInteractiveReports}>
              Обновить все отчёты
            </button>
          </div>

          {reportLoading && <p className="muted">Формирование отчёта...</p>}

          {databaseDashboard && (
            <div className="stats-grid db-metrics-grid compact-metrics-grid">
              <div className="stat-card"><strong>{databaseDashboard.metrics.BookCount}</strong><span>книг</span></div>
              <div className="stat-card"><strong>{databaseDashboard.metrics.UserCount}</strong><span>пользователей</span></div>
              <div className="stat-card"><strong>{formatMoney(databaseDashboard.metrics.TotalSales)}</strong><span>сумма продаж</span></div>
              <div className="stat-card"><strong>{databaseDashboard.metrics.PurchaseCount}</strong><span>покупок</span></div>
              <div className="stat-card"><strong>{databaseDashboard.metrics.PromotionCount}</strong><span>акций</span></div>
              <div className="stat-card"><strong>{databaseDashboard.metrics.AuditLogCount}</strong><span>записей аудита</span></div>
            </div>
          )}

          <div className="interactive-report-grid">
            <div className="interactive-report-card">
              <div className="report-card-header">
                <div>
                  <h3>Продажи за период</h3>
                  <p className="muted">Процедура: dbo.usp_AdminSalesReport</p>
                </div>
              </div>

              <div className="report-filters">
                <label className="field-label">
                  <span>Дата от</span>
                  <input
                    type="date"
                    value={salesReportFilters.start_date}
                    onChange={(e) => updateSalesReportFilter("start_date", e.target.value)}
                  />
                </label>

                <label className="field-label">
                  <span>Дата до</span>
                  <input
                    type="date"
                    value={salesReportFilters.end_date}
                    onChange={(e) => updateSalesReportFilter("end_date", e.target.value)}
                  />
                </label>

                <label className="field-label">
                  <span>Группировка</span>
                  <select
                    value={salesReportFilters.group_by}
                    onChange={(e) => updateSalesReportFilter("group_by", e.target.value)}
                  >
                    <option value="Book">По книгам</option>
                    <option value="User">По пользователям</option>
                    <option value="Day">По дням</option>
                  </select>
                </label>

                <button type="button" onClick={loadSalesReport}>Сформировать</button>
              </div>

              <div className="report-table-wrap">
                <table className="report-table">
                  <thead>
                    <tr>
                      <th>Объект</th>
                      <th>Покупок</th>
                      <th>Сумма</th>
                      <th>Средняя цена</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(salesReport.rows || []).map((row, index) => (
                      <tr key={`${salesReport.group_by}-${index}`}>
                        <td>
                          {row.Title || row.Username || row.SaleDate || `Строка ${index + 1}`}
                          {row.Email && <small>{row.Email}</small>}
                        </td>
                        <td>{row.PurchaseCount}</td>
                        <td>{formatMoney(row.TotalSales)}</td>
                        <td>{formatMoney(row.AveragePurchasePrice)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="interactive-report-card">
              <div className="report-card-header">
                <div>
                  <h3>Отчёт по книгам</h3>
                  <p className="muted">Процедура: dbo.usp_AdminBookReport</p>
                </div>
              </div>

              <div className="report-filters four-columns">
                <label className="field-label">
                  <span>Жанр</span>
                  <input
                    value={bookReportFilters.genre_name}
                    onChange={(e) => updateBookReportFilter("genre_name", e.target.value)}
                    placeholder="Например: Драма"
                  />
                </label>

                <label className="field-label">
                  <span>Издательство</span>
                  <select
                    value={bookReportFilters.publisher_id}
                    onChange={(e) => updateBookReportFilter("publisher_id", e.target.value)}
                  >
                    <option value="">Все</option>
                    {options.publishers.map((publisher) => (
                      <option key={publisher.PublisherId} value={publisher.PublisherId}>
                        {publisher.PublisherName}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field-label">
                  <span>Минимальный рейтинг</span>
                  <input
                    type="number"
                    min="0"
                    max="5"
                    step="0.1"
                    value={bookReportFilters.min_rating}
                    onChange={(e) => updateBookReportFilter("min_rating", e.target.value)}
                    placeholder="0-5"
                  />
                </label>

                <label className="field-label">
                  <span>Скидки</span>
                  <select
                    value={bookReportFilters.only_with_discount}
                    onChange={(e) => updateBookReportFilter("only_with_discount", e.target.value)}
                  >
                    <option value="">Все книги</option>
                    <option value="true">Только со скидкой</option>
                  </select>
                </label>

                <button type="button" onClick={loadBookReport}>Сформировать</button>
              </div>

              <div className="report-table-wrap">
                <table className="report-table wide-report-table">
                  <thead>
                    <tr>
                      <th>Книга</th>
                      <th>Жанры</th>
                      <th>Издательство</th>
                      <th>Цена</th>
                      <th>Рейтинг</th>
                      <th>Покупок</th>
                      <th>Продажи</th>
                    </tr>
                  </thead>
                  <tbody>
                    {bookReport.map((book) => (
                      <tr key={book.BookId}>
                        <td><strong>{book.Title}</strong><small>{book.Authors}</small></td>
                        <td>{book.Genres}</td>
                        <td>{book.PublisherName}</td>
                        <td>
                          {hasBookDiscount(book) ? (
                            <span>{formatMoney(book.Price)} → {formatMoney(book.FinalPrice)}</span>
                          ) : (
                            <span>{formatMoney(book.Price)}</span>
                          )}
                        </td>
                        <td>★ {Number(book.AverageRating || 0).toFixed(2)}</td>
                        <td>{book.PurchaseCount}</td>
                        <td>{formatMoney(book.TotalSales)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="interactive-report-card">
              <div className="report-card-header">
                <div>
                  <h3>Отчёт по пользователям</h3>
                  <p className="muted">Процедура: dbo.usp_AdminUserReport</p>
                </div>
              </div>

              <div className="report-filters four-columns">
                <label className="field-label">
                  <span>Активность</span>
                  <select
                    value={userReportFilters.only_active}
                    onChange={(e) => updateUserReportFilter("only_active", e.target.value)}
                  >
                    <option value="">Все</option>
                    <option value="true">Только активные</option>
                    <option value="false">Только неактивные</option>
                  </select>
                </label>

                <label className="field-label">
                  <span>Мин. сумма покупок</span>
                  <input
                    type="number"
                    min="0"
                    step="1"
                    value={userReportFilters.min_purchase_amount}
                    onChange={(e) => updateUserReportFilter("min_purchase_amount", e.target.value)}
                    placeholder="Например: 500"
                  />
                </label>

                <label className="field-label">
                  <span>Регистрация от</span>
                  <input
                    type="date"
                    value={userReportFilters.registration_start}
                    onChange={(e) => updateUserReportFilter("registration_start", e.target.value)}
                  />
                </label>

                <label className="field-label">
                  <span>Регистрация до</span>
                  <input
                    type="date"
                    value={userReportFilters.registration_end}
                    onChange={(e) => updateUserReportFilter("registration_end", e.target.value)}
                  />
                </label>

                <button type="button" onClick={loadUserReport}>Сформировать</button>
              </div>

              <div className="report-table-wrap">
                <table className="report-table wide-report-table">
                  <thead>
                    <tr>
                      <th>Пользователь</th>
                      <th>Роль</th>
                      <th>Баланс</th>
                      <th>Покупок</th>
                      <th>Сумма</th>
                      <th>Отзывы</th>
                      <th>Избранное</th>
                      <th>Подписки</th>
                    </tr>
                  </thead>
                  <tbody>
                    {userReport.map((user) => (
                      <tr key={user.UserId}>
                        <td><strong>{user.Username}</strong><small>{user.Email}</small></td>
                        <td>{user.RoleName}</td>
                        <td>{formatMoney(user.Balance)}</td>
                        <td>{user.PurchaseCount}</td>
                        <td>{formatMoney(user.TotalPurchaseAmount)}</td>
                        <td>{user.ReviewCount}</td>
                        <td>{user.FavoriteCount}</td>
                        <td>{user.ActiveSubscriptionCount}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="interactive-report-card">
              <div className="report-card-header">
                <div>
                  <h3>Отчёт по жанрам</h3>
                  <p className="muted">Процедура: dbo.usp_AdminGenreReport</p>
                </div>
              </div>

              <div className="report-filters">
                <label className="field-label">
                  <span>Продажи от</span>
                  <input
                    type="date"
                    value={genreReportFilters.start_date}
                    onChange={(e) => updateGenreReportFilter("start_date", e.target.value)}
                  />
                </label>

                <label className="field-label">
                  <span>Продажи до</span>
                  <input
                    type="date"
                    value={genreReportFilters.end_date}
                    onChange={(e) => updateGenreReportFilter("end_date", e.target.value)}
                  />
                </label>

                <button type="button" onClick={loadGenreReport}>Сформировать</button>
              </div>

              <div className="report-table-wrap">
                <table className="report-table">
                  <thead>
                    <tr>
                      <th>Жанр</th>
                      <th>Книг</th>
                      <th>Покупок</th>
                      <th>Продажи</th>
                      <th>Средний рейтинг</th>
                    </tr>
                  </thead>
                  <tbody>
                    {genreReport.map((genre) => (
                      <tr key={genre.GenreId}>
                        <td><strong>{genre.GenreName}</strong></td>
                        <td>{genre.BookCount}</td>
                        <td>{genre.PurchaseCount}</td>
                        <td>{formatMoney(genre.TotalSales)}</td>
                        <td>★ {Number(genre.AverageRating || 0).toFixed(2)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="interactive-report-card">
              <div className="report-card-header">
                <div>
                  <h3>Журнал действий с фильтрами</h3>
                  <p className="muted">Процедура: dbo.usp_AdminAuditLogReport</p>
                </div>
              </div>

              <div className="report-filters four-columns">
                <label className="field-label">
                  <span>Таблица</span>
                  <input
                    value={auditReportFilters.table_name}
                    onChange={(e) => updateAuditReportFilter("table_name", e.target.value)}
                    placeholder="Book, Purchase, Promotion..."
                  />
                </label>

                <label className="field-label">
                  <span>Действие</span>
                  <select
                    value={auditReportFilters.action_name}
                    onChange={(e) => updateAuditReportFilter("action_name", e.target.value)}
                  >
                    <option value="">Все</option>
                    <option value="INSERT">INSERT</option>
                    <option value="UPDATE">UPDATE</option>
                    <option value="DELETE">DELETE</option>
                  </select>
                </label>

                <label className="field-label">
                  <span>Дата от</span>
                  <input
                    type="date"
                    value={auditReportFilters.start_date}
                    onChange={(e) => updateAuditReportFilter("start_date", e.target.value)}
                  />
                </label>

                <label className="field-label">
                  <span>Дата до</span>
                  <input
                    type="date"
                    value={auditReportFilters.end_date}
                    onChange={(e) => updateAuditReportFilter("end_date", e.target.value)}
                  />
                </label>

                <button type="button" onClick={loadAuditReport}>Сформировать</button>
              </div>

              <div className="report-table-wrap">
                <table className="report-table wide-report-table">
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Таблица</th>
                      <th>Действие</th>
                      <th>Запись</th>
                      <th>Описание</th>
                      <th>Дата</th>
                    </tr>
                  </thead>
                  <tbody>
                    {auditReport.map((item) => (
                      <tr key={item.LogId}>
                        <td>{item.LogId}</td>
                        <td>{item.TableName}</td>
                        <td>{item.ActionName}</td>
                        <td>{item.RecordId}</td>
                        <td>{item.Description}</td>
                        <td>{item.CreatedAt}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </section>
      )}

      {activeAdminTab === "sql" && (
        <section className="panel admin-tab-panel">
          <div className="section-heading">
            <div>
              <h2>SQL-объекты проекта</h2>
              <p className="muted">
                Представления, процедуры, функции и триггеры сгруппированы по типам.
                Для каждого объекта указано, зачем он нужен в проекте и где используется.
              </p>
            </div>

            <button type="button" className="secondary" onClick={loadDatabaseDashboard}>
              Обновить список
            </button>
          </div>

          {databaseDashboard ? (
            <div className="sql-object-groups">
              {sqlObjectGroups.map((group) => (
                <section key={group.objectType} className="sql-object-group">
                  <div className="sql-object-group-header">
                    <div>
                      <h3>{group.label}</h3>
                      <p className="muted">{group.description}</p>
                    </div>

                    <span className="sql-object-count">{group.items.length}</span>
                  </div>

                  <div className="sql-object-cards">
                    {group.items.map((object) => (
                      <article
                        key={`${object.ObjectType}-${object.ObjectName}`}
                        className="sql-object-card"
                      >
                        <div className="sql-object-card-title">
                          <strong>{object.ObjectName}</strong>
                          <span>{getSqlObjectTypeLabel(object.ObjectType)}</span>
                        </div>

                        <p className="sql-object-summary">{getSqlObjectDescription(object)}</p>

                        <button
                          type="button"
                          className="secondary small-button sql-details-button"
                          onClick={() => setSelectedSqlObject(object)}
                        >
                          Подробнее
                        </button>

                        <div className="sql-object-card-meta">
                          <span>Создан: {object.CreatedAt}</span>
                          <span>Изменён: {object.ModifiedAt}</span>
                        </div>
                      </article>
                    ))}
                  </div>
                </section>
              ))}
            </div>
          ) : (
            <p className="muted">SQL-объекты загружаются...</p>
          )}
        </section>
      )}

      {activeAdminTab === "audit" && (
      <section className="panel">
        <h2>AuditLog</h2>
        <p className="muted">
          Здесь отображаются действия, которые записали триггеры SQL Server.
        </p>

        {auditLog.map((log) => (
          <div key={log.LogId} className="audit-card">
            <strong>
              #{log.LogId} — {log.TableName} / {log.ActionName}
            </strong>
            <p>{log.Description}</p>
            <span>{log.CreatedAt}</span>
          </div>
        ))}
      </section>
      )}


      <SqlObjectDetailsModal
        object={selectedSqlObject}
        onClose={() => setSelectedSqlObject(null)}
      />
    </Layout>
  );
}

function LoginPage() {
  const navigate = useNavigate();

  const [login, setLogin] = useState("giorgi");
  const [password, setPassword] = useState("1234");
  const [error, setError] = useState("");

  async function loginUser() {
    try {
      setError("");

      const response = await api.post("/users/login", {
        login,
        password,
      });

      saveCurrentUser(response.data);

      navigate("/");
      window.location.reload();
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  return (
    <Layout>
      <section className="panel small-panel">
        <h1>Вход</h1>

        <p className="muted">
          Обычный пользователь: giorgi / 1234. Администратор: admin / admin123.
        </p>

        <label className="field-label">
          <span>Логин или Email</span>
          <input
            value={login}
            onChange={(e) => setLogin(e.target.value)}
            placeholder="giorgi"
          />
        </label>

        <label className="field-label">
          <span>Пароль</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="1234"
          />
        </label>

        <button type="button" onClick={loginUser}>
          Войти
        </button>

        {error && <p className="error">{error}</p>}
      </section>
    </Layout>
  );
}

function RegisterPage() {
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("1234");
  const [dateOfBirth, setDateOfBirth] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function registerUser() {
    try {
      setMessage("");
      setError("");

      const response = await api.post("/users/register", {
        username,
        email,
        password,
        date_of_birth: dateOfBirth || null,
      });

      setMessage(`Пользователь создан. UserId = ${response.data.UserId}`);
      setUsername("");
      setEmail("");
      setPassword("1234");
      setDateOfBirth("");
    } catch (err) {
      setError(err.response?.data?.detail || err.message);
    }
  }

  return (
    <Layout>
      <section className="panel small-panel">
        <h1>Регистрация</h1>

        <label className="field-label">
          <span>Username</span>
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="Username"
          />
        </label>

        <label className="field-label">
          <span>Email</span>
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="Email"
          />
        </label>

        <label className="field-label">
          <span>Дата рождения</span>
          <input
            type="date"
            value={dateOfBirth}
            onChange={(e) => setDateOfBirth(e.target.value)}
          />
        </label>

        <label className="field-label">
          <span>Password</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Password"
          />
        </label>

        <button onClick={registerUser}>Зарегистрироваться</button>

        {message && <p className="success">{message}</p>}
        {error && <p className="error">{error}</p>}
      </section>
    </Layout>
  );
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<CatalogPage />} />
        <Route path="/books/:bookId" element={<BookDetailsPage />} />
        <Route path="/library/:userId" element={<LibraryPage />} />
        <Route path="/favorites/:userId" element={<FavoritesPage />} />
        <Route path="/profile/:userId" element={<ProfilePage />} />
        <Route path="/reader/:bookId" element={<ReaderPage />} />
        <Route path="/subscriptions" element={<SubscriptionsPage />} />
        <Route path="/admin" element={<AdminPage />} />
        <Route path="/login" element={<LoginPage />} />
        <Route path="/register" element={<RegisterPage />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
