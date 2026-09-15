# Otmena

**Otmena** — программа для Windows, которая помогает открыть **Discord**, **YouTube** и **Telegram**, когда они заблокированы провайдером или корпоративной политикой.

Один файл `Otmena.exe`, без установки в систему. Запустил — нажал **Запустить** — сервисы сами подбирают рабочий способ подключения.

> Основано на [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) **1.10.1**, доработано под удобный запуск с рабочих ПК. Telegram и Cursor идут через ключ [vpn.dance](https://vpn.dance) (VLESS Reality, Польша).

---

## Что умеет

| Сервис | Как работает |
|--------|----------------|
| **Discord / YouTube** | Обход DPI через `winws.exe` (нужны права администратора) |
| **Telegram** | Локальный SOCKS через VLESS (xray + ключ vpn.dance) или резервный MTProto-прокси |
| **Авто-переключение** | Если один способ не сработал — пробует следующий |
| **Автозапуск** | Можно включить при входе в Windows |
| **Обновления** | Кнопка **Обновления** — скачивает новую версию с GitHub |

---

## Системные требования

- **Windows 10 / 11** (64-bit)
- **Права администратора** — для Discord и YouTube (WinDivert)
- **Telegram Desktop** — для прокси (лучше с [desktop.telegram.org](https://desktop.telegram.org), не из Microsoft Store)
- ~150 МБ на диске (вместе с компонентами)

---

## Установка

### Вариант 1 — из Releases (рекомендуется)

1. Открой [Releases](https://github.com/Qylosez/otmena-releases/releases).
2. Скачай **`Otmena-update.zip`** (~3–4 МБ, без xray — так проще залить на GitHub).
3. Распакуй, например в `C:\Otmena\`.
4. Запусти **`Otmena.exe`** от администратора.
5. При первом запуске **xray** для Telegram скачается сам (нужен `xray-windows-64.zip` в Releases или доступ к GitHub).
6. Быстрый патч на чужой ПК: `utils\deploy-hotfix.ps1 -TargetFolder "D:\путь\к\Otmena"`.

> Не клади папку в `Program Files` — так проще обновлять и удалять.

### Вариант 2 — уже есть папка от коллеги

Скопируй всю папку на свой ПК и запусти `Otmena.exe`. Больше ничего ставить не нужно.

---

## Первый запуск

1. **ПКМ → Запуск от имени администратора** (важно для Discord/YouTube).
2. При первом открытии появится подсказка — можно сворачивать в **трей** при закрытии окна.
3. Нажми **▶ Запустить**.
4. Смотри на плитки статуса вверху:

| Плитка | Зелёный | Красный |
|--------|---------|---------|
| **Discord / YouTube** | Обход работает | Не запустился (см. [проблемы](#частые-проблемы)) |
| **Telegram** | Прокси поднят | Нужна ручная настройка MTProto |
| **Права** | Запущено от админа | Запусти от администратора |
| **Автозапуск** | Включён | Выключен |
| **Work mode** | Режим для рабочего ПК | Обычный режим |

5. Для Telegram, если не заработало само — **Добавить MTProto в Telegram** и включи прокси в приложении.

Ключ VLESS берётся из подписки vpn.dance (`telegram-vless\subscription.json`). При **Запустить** Otmena обновляет профили (TCP Reality 8444, gRPC 8443, WS 8447) и поднимает SOCKS `127.0.0.1:10808` / HTTP `10809`.

---

## Интерфейс — что нажимать

### Действия
- **Запустить** — включить Discord/YouTube + Telegram (с авто-переключением способов).
- **Остановить** — выключить всё.
- **Проверить** — тест всех методов с результатом ✓/✗ в журнале.

### Telegram
- **Добавить MTProto в Telegram** — добавить прокси `proxy-dag.ru` в Telegram. Если не откроется автоматически — покажет данные для ручного ввода.

### Система
- **Автозапуск ВКЛ / ВЫКЛ** — запуск Otmena при входе в Windows.
- **Work mode** — для **рабочих ПК** с Secret Net и блокировкой служб Windows (см. ниже).
- **От администратора** — перезапуск с правами админа.
- **Cursor exclude** — если после запуска Otmena перестал работать **Cursor** или другая IDE.
- **Диагностика** — скопировать отчёт в буфер (удобно отправить тому, кто настраивал).
- **Обновления** — проверить и установить новую версию с GitHub.
- **Выключить всё** — остановить, не удаляя папку.
- **Удалить Otmena** — полная очистка и удаление папки.

### Трей
Закрытие окна **не выключает** программу — она остаётся в трее (иконка у часов).  
Двойной клик по иконке — снова открыть окно.

Запуск сразу в трей:
```text
Otmena.exe /minimized
```

---

## Рабочий компьютер (Secret Net, корпоративная сеть)

На многих рабочих ПК **Discord и YouTube не заработают** — антivirus или Secret Net блокирует драйвер WinDivert. **Telegram обычно можно настроить.**

Что делать:

1. Включи **Work mode** (кнопка в разделе «Система»).
2. Нажми **Запустить**.
3. Если **Discord / YouTube** красный — на этом ПК они, скорее всего, недоступны. Используй **только Telegram**.
4. **MTProto вручную** в Telegram:
   - Настройки → Данные и память → Использование прокси → MTProto
   - Сервер: `proxy-dag.ru`
   - Порт: `443`
   - Secret: `ee94fc2b484af6e1e1c87e6576b33c257579612e7275`
5. Если **xray** не качается (GitHub заблокирован) — скачай [Xray-core](https://github.com/XTLS/Xray-core/releases) на другом ПК и положи `xray.exe` в папку `telegram-vless\bin\`.

---

## Work mode и Cursor exclude — простыми словами

**Work mode** — режим без службы Windows. Нужен на ПК с Secret Net, где системные службы запрещены. Включай на рабочих компах.

**Cursor exclude** — добавляет Cursor/IDE в исключения, чтобы Otmena не ломала интернет в редакторе кода. Жми, если Cursor тормозит после запуска Otmena.

---

## Обновления

В приложении уже настроен канал обновлений. Достаточно:

1. Открыть **Otmena.exe**
2. Нажать **Обновления**
3. Если есть новая версия — **Да**

Программа скачает архив, установит и перезапустится.  
Твои локальные настройки (work mode, Telegram, xray) сохраняются.

Если кнопка пишет **Ошибка установки (код 1)** — с этого ПК GitHub не качается напрямую. Запусти **`FIX-UPDATE.bat`** в папке Otmena (берёт zip через зеркала). Либо **Запустить всё** и **`DOWNLOAD-UPDATE.bat`**.

---

## Частые проблемы

### Discord / YouTube не работают
- Запусти **от администратора**.
- На рабочем ПК WinDivert часто **заблокирован** — это нормально, используй Telegram.
- Нажми **Проверить** и посмотри журнал внизу.

### «Не удалось добавить MTProto (код 2)»
Telegram не принимает ссылки `tg://`. Установи Telegram Desktop с [desktop.telegram.org](https://desktop.telegram.org) и добавь прокси **вручную** (данные выше).

### Telegram красный, xray не стартует
- Проверь, есть ли файл `telegram-vless\bin\xray.exe`.
- На закрытой сети положи `xray.exe` вручную.
- Или используй только **MTProto**.

### Программа «зависает» при запуске
Подожди 2–3 секунды — идёт фоновая проверка статуса. Окно должно открыться сразу.

### Нужна помощь
Нажми **Диагностика** — отчёт скопируется в буфер. Отправь тому, кто выдал тебе Otmena.

---

## Удаление

**Выключить всё** — остановить процессы, оставить папку.

**Удалить Otmena с компьютера** — остановить всё и удалить папку целиком (нужен администратор).

---

## Структура папки

```text
Otmena.exe              ← запускай это
bin\                    ← движок обхода (winws, WinDivert)
lists\                  ← списки сайтов
telegram-vless\         ← xray + подписка vpn.dance (Telegram и Cursor)
utils\                  ← служебные скрипты (не трогать без нужды)
scripts\                ← внутренние bat-файлы
```

---

## Как выложить на GitHub (один репозиторий)

Используется **только** [Qylosez/otmena-releases](https://github.com/Qylosez/otmena-releases):
- **README** — описание на главной репозитория
- **Releases** — готовый zip для скачивания и кнопки «Обновления»

Через браузер zip **> 25 МБ** не залить — только через команду ниже.

### Один раз — настройка

1. Создай репозиторий: https://github.com/new → имя **`otmena-releases`** → Public → без README
2. Установи и войди:
   ```powershell
   winget install Git.Git
   winget install GitHub.cli
   gh auth login
   ```
3. Залей README на GitHub:
   ```powershell
   cd C:\Users\пользователь\Desktop\zapret4
   git init
   git add README.md
   git commit -m "README"
   git branch -M main
   git remote add origin https://github.com/Qylosez/otmena-releases.git
   git push -u origin main
   ```

### Каждый раз — когда обновил программу

```powershell
cd C:\Users\пользователь\Desktop\zapret4\app
.\build-app.ps1

cd ..\utils
.\publish-update.ps1 -GitHubRepo "Qylosez/otmena-releases" -Bump
```

**Один раз** (и при обновлении Xray) — положи в тот же Release файл **`xray-windows-64.zip`** (~35 МБ), чтобы у пользователей xray ставился при первом запуске:

```powershell
.\publish-xray-asset.ps1 -PublishPath "$env:USERPROFILE\Desktop\otmena-publish"
```

Загрузи `xray-windows-64.zip` в Release рядом с `Otmena-update.zip` (через Draft release → Attach).

Если менял README:
```powershell
cd C:\Users\пользователь\Desktop\zapret4
git add README.md
git commit -m "update readme"
git push
```

### Что говорить людям

> Скачай **Otmena-update.zip** из [Releases](https://github.com/Qylosez/otmena-releases/releases) → распакуй → **Otmena.exe** от администратора.  
> Обновления — кнопка **Обновления** в программе.

---

## Для maintainer'а

---

## Благодарности

- [Flowseal / zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) — ядро обхода DPI
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — прокси для Telegram

---

## Автор

[Qylosez](https://github.com/Qylosez)

Если нашёл баг — создай Issue в [otmena-releases](https://github.com/Qylosez/otmena-releases/issues).
