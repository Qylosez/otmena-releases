Otmena

Приложение для обхода блокировок Discord, YouTube и настройки Telegram на Windows.

Быстрый старт





Запустите Otmena.exe от имени администратора (нужно для Discord/YouTube).



Нажмите Запустить — приложение само переберёт рабочие способы.



Для Telegram: если VLESS не поднялся, нажмите Добавить MTProto в Telegram и включите proxy в приложении.

Рабочий ПК / Secret Net

На корпоративных компьютерах с Secret Net Studio:





При первом запуске включите Work mode — служба Windows не используется.



WinDivert часто блокируется — тогда остаётся только Telegram (VLESS или MTProto).



Автозапуск: если задача в планировщике не создаётся, используется ярлык в папке «Автозагрузка».



xray.exe: на закрытых сетях GitHub недоступен. Скачайте Xray-core на другом ПК и положите xray.exe в telegram-vless\bin\.

Кнопки







Кнопка



Действие





Запустить



DS/YT + Telegram с авто-переключением





Остановить



Останавливает winws, xray, прокси





Проверить



Тест всех способов с результатом OK/FAIL





Work mode



Режим без службы Windows (для Secret Net)





Автозапуск ВКЛ



Задача планировщика или Startup





Диагностика



Копирует отчёт в буфер обмена





Обновления



Проверка и установка с GitHub





Cursor exclude



Исключения для Cursor/IDE





Выключить всё



Остановка без удаления папки





Удалить



Полная очистка и удаление папки

Трей

При закрытии окна Otmena сворачивается в трей.
Запуск свёрнутым: Otmena.exe /minimized

Структура

Otmena.exe          — главное приложение
bin\                — winws.exe, WinDivert
lists\              — списки доменов/IP
telegram-vless\     — конфиг и xray
utils\              — скрипты (launcher, статус, Telegram)
scripts\            — служебные bat

Обновления через GitHub

Один раз





Создай репозиторий: otmena-releases (Public)



gh auth login



В utils\update-config.json на всех ПК:

 { "enabled": true, "githubRepo": "Qylosez/otmena-releases" }

Публикация (твой ПК)

cd app
.\build-app.ps1

cd ..\utils
.\publish-update.ps1 -GitHubRepo "Qylosez/otmena-releases" -Bump

На других ПК

Обновления → Да



Версия

Основа: zapret-discord-youtube 1.9.8c
