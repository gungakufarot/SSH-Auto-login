#!/usr/bin/env bash
set -euo pipefail
echo "=== Автонастройка SSH (Linux/Termux) ==="
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "ВНИМАНИЕ: скрипт запущен от root."
  echo "Все ключи и конфиги будут сохранены в /root/.ssh."
  read -rp "Продолжить? [y/N]: " ans
  case "$ans" in
    [Yy]* ) echo "Ок, работаем дальше как root." ;;
    * ) echo "Отмена по запросу пользователя."; exit 1 ;;
  esac
fi
for cmd in ssh ssh-keygen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Ошибка: команда '$cmd' не найдена. Установите её и повторите попытку."
    exit 1
  fi
done
SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
find_free_keyfile() {
  local base="$SSH_DIR/id_ed25519"
  if [ ! -e "$base" ] && [ ! -e "$base.pub" ]; then
    echo "$base"
    return
  fi
  local i=1
  while :; do
    local cand="${base}_${i}"
    if [ ! -e "$cand" ] && [ ! -e "$cand.pub" ]; then
      echo "$cand"
      return
    fi
    i=$((i+1))
  done
}
KEY_FILE=""
PUB_KEY=""
if [ -f "$SSH_DIR/id_ed25519" ] && [ -f "$SSH_DIR/id_ed25519.pub" ]; then
  KEY_FILE="$SSH_DIR/id_ed25519"
  PUB_KEY="$SSH_DIR/id_ed25519.pub"
  echo "Найден существующий ключ: $KEY_FILE — будем использовать его."
else
  KEY_FILE="$(find_free_keyfile)"
  PUB_KEY="${KEY_FILE}.pub"
  echo "Создаю новый ключ: $KEY_FILE"
  ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "auto-setup-$(date +%Y%m%d%H%M%S)"
fi
echo "Публичный ключ: $PUB_KEY"
SERVER_HOST=""
SERVER_USER=""
while :; do
  read -rp "Введите IP или домен сервера: " SERVER_HOST
  read -rp "Введите имя пользователя на сервере: " SERVER_USER

  echo "Пробуем подключиться к ${SERVER_USER}@${SERVER_HOST} (ssh может спросить пароль и/или подтверждение ключа хоста)..."
  if ssh -o BatchMode=no -o ConnectTimeout=10 "${SERVER_USER}@${SERVER_HOST}" "exit" 2>/dev/null; then
    echo "Успешно подключились к серверу."
    break
  else
    echo "Данные для подключения не верны, повторите попытку снова."
  fi
done
echo "Копирую SSH-ключ на сервер (нужно будет ввести пароль ещё раз)..."
if command -v ssh-copy-id >/dev/null 2>&1; then
  if ssh-copy-id -i "$PUB_KEY" "${SERVER_USER}@${SERVER_HOST}"; then
    echo "Ключ успешно скопирован с помощью ssh-copy-id."
  else
    echo "Не удалось скопировать ключ с помощью ssh-copy-id."
    exit 1
  fi
else
  if ssh "${SERVER_USER}@${SERVER_HOST}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" < "$PUB_KEY"; then
    echo "Ключ успешно скопирован вручную."
  else
    echo "Не удалось скопировать ключ на сервер."
    exit 1
  fi
fi
CONFIG_FILE="$SSH_DIR/config"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
read -rp "Как назвать хост (alias для ssh, например: ubuntu): " HOST_ALIAS
{
  echo ""
  echo "Host $HOST_ALIAS"
  echo "    HostName $SERVER_HOST"
  echo "    User $SERVER_USER"
  echo "    IdentityFile $KEY_FILE"
  echo "    IdentitiesOnly yes"
} >> "$CONFIG_FILE"
echo
echo "Готово!"
echo "Теперь вы можете подключаться к серверу командой:"
echo "  ssh $HOST_ALIAS"
echo
echo "Конфиг: $CONFIG_FILE"
echo "Ключ:   $KEY_FILE"
