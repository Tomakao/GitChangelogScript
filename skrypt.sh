#!/bin/bash

#Definicje
JIRA_BASE_URL="https://rg-plus.atlassian.net/browse"

COMMIT_HASHES=true             
# true - dodaje linki do commitów,      false - wyświetla tylko tekst commitu
COMMIT_LINK_END_LINE=true      
# true - przenosi link na koniec linii, false - wyświetla link na początku linii
JIRA=true                       
# true - dodaje linki do JIRA,          false - usuwa wszystkie tagi [XYZ-123] JIRA
JIRA_ON=true
# true - włącza formatowanie i obsługę JIRA,         false - wyłącza obsługę JIRA
GIT_ISSUE_LINK=true             
# true - dodaje linki do issue,         false - nie dodaje linków do issue
ALL_COMMITS=false               
# true - wyświetla wszystkie commity,   false - wyświetla tylko filtrowane commity
PREFIX=true                     
# true - dodatkowe usuwanie wyłączone,  false - usuwa wszystkie prefiksy
FETCH_TAGS=true                 
# true - pobiera tagi z repozytorium,   false - nie pobiera tagów

# Użytkownik może zdefiniować tutaj prefixy, które chce filtrować
PREFIXES=("fix" "feat" "chore" "other") # prefixy dodawane do pliku CHANGELOG.md. Ignorowane gdy ALL_COMMITS=true
OTHER_PREFIX="other" # dodawany do linijek bez innych prefixów dla odróżnienia i dołączenia do filtrowanych

# Funkcja sprawdzająca, czy można edytować plik bez sudo
can_edit_without_sudo() {
    [[ -w "$1" ]]
}

#test

# Funkcja do sprawdzania dostępności edytora
choose_editor() {
    if command -v gedit >/dev/null 2>&1; then
        echo "gedit"
    elif command -v kate >/dev/null 2>&1; then
        echo "kate"
    elif command -v subl >/dev/null 2>&1; then
        echo "subl"  # Sublime Text
    elif command -v atom >/dev/null 2>&1; then
        echo "atom"
    elif command -v xed >/dev/null 2>&1; then
        echo "xed"  # Mint's Xed Editor
    elif command -v mousepad >/dev/null 2>&1; then
        echo "mousepad"  # XFCE's Mousepad
    elif command -v nano >/dev/null 2>&1; then
        echo "nano"
    elif command -v vi >/dev/null 2>&1; then
        echo "vi"
    elif command -v emacs >/dev/null 2>&1; then
        echo "emacs"
    else
        echo "Nie znaleziono edytora (gedit/kate/subl/atom/xed/mousepad/nano/vi/emacs)" >&2
        exit 1
    fi
}

# Funkcja wyświetlająca pomoc
show_help() {
    echo -e "\e[1;36mUżycie skryptu i dostępne opcje:\e[0m"
    echo -e "\e[1;33m+l, --link\e[0m:\t\t Włącza dodawanie skróconych linków commitów do wiadomości."
    echo -e "\e[1;33m-l, --no-link\e[0m:\t\t Wyłącza dodawanie skróconych linków commitów do wiadomości."
    echo -e "\e[1;33m+k, --link-koniec\e[0m:\t Włącza umieszczanie skróconych linków commitów na końcu wiadomości."
    echo -e "\e[1;33m-k, --no-link-koniec\e[0m:\t Wyłącza umieszczanie skróconych linków commitów na końcu wiadomości."
    echo -e "\e[1;33m+j, --jira\e[0m:\t\t Formatuje i linkuje tagi JIRA."
    echo -e "\e[1;33m-j, --no-jira\e[0m:\t\t Usuwa tagi JIRA."
    echo -e "\e[1;33m+i, --issue\e[0m:\t\t Włącza dodawanie linków do issue na GitHub."
    echo -e "\e[1;33m-i, --no-issue\e[0m:\t\t Wyłącza dodawanie linków do issue na GitHub."
    echo -e "\e[1;33m+p, --prefix\e[0m:\t\t Wyłącza usuwanie prefiksów z commitów."
    echo -e "\e[1;33m-p, --no-prefix\e[0m:\t Usuwa wszystkie prefiksy z commitów."
    echo -e "\e[1;33m+a, --all\e[0m:\t\t Włącza przetwarzanie wszystkich commitów, niezależnie od prefiksów."
    echo -e "\e[1;33m-a, --no-all\e[0m:\t\t Wyłącza przetwarzanie wszystkich commitów."
    echo -e "\e[1;33m+f, --fetch\e[0m:\t\t Włącza pobieranie tagów z git."
    echo -e "\e[1;33m-f, --no-fetch\e[0m:\t\t Wyłącza pobieranie tagów z git."
    echo -e "\e[1;33m-c, --config\e[0m:\t\t Włącza tryb edycji konfiguracji skryptu."
    echo -e "\e[1;33m--config <edytor>\e[0m:\t Włącza tryb edycji konfiguracji skryptu z wybranym edytorem."
    echo -e "\e[1;32mFlagi można łączyć, np. +l +k +j -p -a lub +lkj -pa.\e[0m"
    echo -e "\e[1;32mAby wyświetlić tę pomoc, użyj: -h, --help\e[0m"
}

config_requested=false

# Przetwarzanie argumentów
while [[ $# -gt 0 ]]; do
    key="$1"

    if [[ $key == --* ]]; then
        # Przetwarzanie długich flag
        case $key in
            --link)
            COMMIT_HASHES=true
            ;;
            --link-koniec)
            COMMIT_HASHES=true
            COMMIT_LINK_END_LINE=true
            ;;
            --no-link-koniec)
            COMMIT_HASHES=false
            COMMIT_LINK_END_LINE=false
            ;;
            --no-link)
            COMMIT_HASHES=false
            ;;
            --no-jira)
            JIRA=false
            ;;
            --jira)
            JIRA=true
            ;;
            --no-issue)
            GIT_ISSUE_LINK=false
            ;;
            --issue)
            GIT_ISSUE_LINK=true
            ;;
            --no-prefix)
            PREFIX=false
            ;;
            --prefix)
            PREFIX=true
            ;;
            --no-all)
            ALL_COMMITS=false
            ;;
            --all)
            ALL_COMMITS=true
            ;;
            --no-fetch)
            FETCH_TAGS=false
            ;;
            --fetch)
            FETCH_TAGS=true
            ;;
            --config)
            config_requested=true
            # Sprawdzanie, czy następny argument jest dostępnym edytorem
            if [[ $# -gt 1 ]]; then
                next_arg="${@:2:1}"
                if command -v "$next_arg" >/dev/null 2>&1; then
                    editor_choice="$next_arg"
                    shift # Przesunięcie argumentów, ponieważ następny argument został użyty
                fi
            fi
            ;;
            --help)
            show_help
            exit 0
            ;;
            *)
            # Nieznana długa flaga
            ;;
        esac
    elif [[ $key == -* ]] || [[ $key == +* ]]; then
        sign=${key:0:1}  # Pobierz znak + lub -
        flags=${key:1}   # Pobierz flagi po znaku

        # Przetwarzanie łączonych krótkich flag
        for (( i=0; i<${#flags}; i++ )); do
            char=${flags:$i:1}

            # Ustawianie wartości zmiennych na podstawie znaku
            value=false
            [[ $sign == '+' ]] && value=true

            case $char in
                l)
                COMMIT_HASHES=$value
                ;;
                k)
                COMMIT_LINK_END_LINE=$value
                ;;
                j)
                JIRA=$value
                ;;
                i)
                GIT_ISSUE_LINK=$value
                ;;
                p)
                PREFIX=$value
                ;;
                a)
                ALL_COMMITS=$value
                ;;
                f)
                FETCH_TAGS=$value
                ;;
                c)
                config_requested=true
                ;;
                h)
                show_help
                exit 0
                ;;
                *)
                # Nieznana krótka flaga
                ;;
            esac
        done
    fi
    shift # przesuń argumenty
done

# Definicje kolorów
BLUE='\e[36m'
RED='\e[31m'
GREEN='\e[32m'
NO_COLOR='\e[0m'

# Wyświetlanie szczegółowych informacji o konfiguracji
echo -e "${BLUE}Aktualna konfiguracja:${NO_COLOR}"

if [[ $COMMIT_HASHES == true ]]; then
    echo -e "(l) Linki commitów: ${GREEN}włączone${NO_COLOR}"
else
    echo -e "(l) Linki commitów: ${RED}wyłączone${NO_COLOR}"
fi

if [[ $COMMIT_LINK_END_LINE == true ]]; then
    echo -e "(k) Linki commitów na końcu: ${GREEN}włączone${NO_COLOR}"
else
    echo -e "(k) Linki commitów na końcu: ${RED}wyłączone${NO_COLOR}"
fi

if [[ $JIRA == true ]]; then
    echo -e "(j) Tagi JIRA: ${GREEN}włączone${NO_COLOR}"
else
    echo -e "(j) Tagi JIRA: ${RED}wyłączone${NO_COLOR}"
fi

if [[ $GIT_ISSUE_LINK == true ]]; then
    echo -e "(i) Linki issue: ${GREEN}włączone${NO_COLOR}"
else
    echo -e "(i) Linki issue: ${RED}wyłączone${NO_COLOR}"
fi

if [[ $PREFIX == false ]]; then
    echo -e "(p) Usuwanie prefixów: ${GREEN}włączone${NO_COLOR}"
else
    echo -e "(p) Usuwanie prefixów: ${RED}wyłączone${NO_COLOR}"
fi

if [[ $ALL_COMMITS == true ]]; then
    echo -e "(a) Wszystkie commity: ${GREEN}włączone${NO_COLOR}"
else
    echo -e "(a) Wszystkie commity: ${RED}wyłączone${NO_COLOR}"
fi

if [[ $FETCH_TAGS == true ]]; then
    echo -e "(f) Pobieranie tagów: ${GREEN}włączone${NO_COLOR}"
else
    echo -e "(f) Pobieranie tagów: ${RED}wyłączone${NO_COLOR}"
fi

edit_config() {
    # Pytanie o edycję
    read -p "Czy chcesz edytować konfigurację? (y/n): " answer
    case $answer in
        [Yy]*|[Tt]*|[Yy][Ee][Ss]|[Tt][Aa][Kk])
            # Jeśli wybrano edytor
            if [[ -n $editor_choice ]]; then
                EDITOR=$editor_choice
            else
                EDITOR=$(choose_editor)
            fi

            if can_edit_without_sudo "$0"; then
                $EDITOR "$0"
            else
                sudo $EDITOR "$0"
            fi
            exit 0
            ;;
        *)
            echo "Wyjście bez edycji."
            exit 0
            ;;
    esac
}

# Funkcja pytająca o edycję
if [[ $config_requested == true ]]; then
    edit_config
    exit 0
fi

# Escape'owanie znaków specjalnych w URL dla użycia w wyrażeniach regularnych
ESCAPED_JIRA_BASE_URL=$(echo "$JIRA_BASE_URL" | sed 's/[\/&]/\\&/g')

# Funkcja add_other_prefix
# Ta funkcja dodaje prefix 'other' do commitów, które nie pasują do predefiniowanych wzorców.
# Służy do oznaczania commitów, które nie zawierają żadnego z określonych prefixów (np. fix, feat).
# 1. Przetwarza każdy wiersz wejściowy (commit) osobno.
# 2. Sprawdza, czy commit zawiera już jakiś prefix (sprawdza obecność ':' jako separatora prefixu).
# 3. Jeśli commit nie ma prefixu, dodaje do niego prefix 'other'.
add_other_prefix() {
    awk -F: -v other_prefix="$OTHER_PREFIX" '{
        if (NF>1) print $0; else print other_prefix ": "$0;
    }'
}

# Funkcja filter_commits
# Ta funkcja filtruje commity według określonych typów, zdefiniowanych w zmiennej PREFIXES.
# Umożliwia filtrowanie commitów, które zawierają jeden z określonych prefixów (np. fix, feat, chore).
# 1. Tworzy wyrażenie regularne na podstawie listy prefixów.
# 2. Używa grep z tym wyrażeniem regularnym do filtrowania commitów.
filter_commits() {
    local prefixes_regex=$(printf "|%s" "${PREFIXES[@]}")
    prefixes_regex="${prefixes_regex:1}"
    grep -E "($prefixes_regex)\(.*\):|($prefixes_regex):"
}

# Funkcja format_commits
# Ta funkcja służy do formatowania komunikatów commitów zgodnie z ustaloną konwencją.
# 1. Rozpoznaje i formatuje komunikaty zaczynające się od standardowych prefiksów (np. fix, feat, chore).
#    a. Wyodrębnia i formatuje prefiksy wraz z ewentualnymi identyfikatorami w nawiasach (np. feat(scope): message -> scope: message).
#    b. Usuwa same prefiksy z początku komunikatu, pozostawiając samą treść komunikatu.
# 2. Używa wyrażenia regularnego opartego na zdefiniowanych prefixach do identyfikacji i formatowania.
format_commits() {
    local prefixes_regex=$(printf "|%s" "${PREFIXES[@]}")
    prefixes_regex="${prefixes_regex:1}"
    sed -E "s/\b($prefixes_regex)\(([^)]+)\):([^:]+)/\2: \3/g" \
    | sed -E "s/\b(($prefixes_regex):)//g"
}

# Funkcja remove_prefixes
#Ta funkcja służy do usuwania wszystkich napotkanych prefixów gdy PREFIX jest false
remove_prefixes() {
    sed -E "s/\b([a-zA-Z]+)\(([^)]+)\):([^:]+)/\2: \3/g" \
    | sed -E "s/\b([a-zA-Z]+):\s*//g"
}

# Funkcja trim_spaces
# Ta funkcja usuwa nadmiarowe spacje na początku i na końcu każdej linii tekstu.
# 1. Usuwa wszystkie spacje na początku linii.
# 2. Usuwa wszystkie spacje na końcu linii.
trim_spaces() {
    sed 's/^ *//' \
    | sed 's/ $//'
}

# Funkcja highlight_identifiers
# Ta funkcja wyróżnia identyfikatory JIRA i GitHub w komunikatach commitów, otaczając je nawiasami kwadratowymi.
# 1. Wyszukuje wzorce odpowiadające identyfikatorom (np. ABC-123) i otacza je nawiasami kwadratowymi.
# 2. Zapobiega podwójnemu otoczeniu nawiasami kwadratowymi, jeśli identyfikator już jest otoczony nawiasami.
highlight_identifiers() {
    sed -E 's/\b([A-Z]+-[0-9]+)\b/[\1]/g' \
    | sed -E 's/\[\[([A-Z]+-[0-9]+)\]\]/[\1]/g'
}

# Funkcja extract_and_format_tags
# Ta funkcja służy do wyodrębniania i formatowania tagów JIRA i GitHub z linii tekstu
# 1. Każda linia tekstu jest przetwarzana oddzielnie.
#    a. Usuwa spacje na początku i na końcu linii, aby uporządkować tekst.
# 2. Wyszukuje tagi JIRA/GitHub w linii, które są w formacie [XYZ-123], gdzie XYZ to prefiks, a 123 to numer.
#    a. Wyodrębnia każdy znaleziony tag z linii, jednocześnie zachowując oryginalną treść linii bez tagów.
#    b. Dodaje wyodrębnione tagi do osobnej listy, rozdzielając je spacjami.
# 3. Po przetworzeniu całej linii i wyodrębnieniu wszystkich tagów:
#    a. Jeśli w linii znaleziono tagi, dodaje je z powrotem na końcu tej linii, umieszczając je w nawiasach kwadratowych i oddzielając od treści linii.
#    b. Jeśli w linii nie znaleziono żadnych tagów, wypisuje linię bez zmian.
# Wynikowa linia zawiera oryginalny tekst z ewentualnie dołączonymi na końcu sformatowanymi tagami.
extract_and_format_tags() {
    awk -v jira="$JIRA" '{
        line = $0; # Zapisz linię do zmiennej
        gsub(/^ +| +$/, "", line); # Przytnij spacje na początku i końcu
        tags = "";

        while (match(line, /\[[A-Z]+-[0-9]+\]/)) { # Znajdź tagi JIRA/GitHub
            tag = substr(line, RSTART, RLENGTH); # Wyodrębnij tag
            if (jira == "false") {
                line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH); # Usuń tag JIRA z linii
            } else {
                line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH); # Usuń tag z linii
                tags = tags tag " "; # Dodaj tag do listy tagów
            }
        }

        gsub(/ +$/, "", tags); # Przytnij spacje na końcu listy tagów

        if (jira == "true" && tags != "") {
            print line " \\[" tags "\\]"; # Wypisz linię z tagami
        } else {
            print line; # Wypisz linię bez tagów JIRA
        }
    }'
}


# Funkcja additional_formatting
# Ta funkcja wykonuje serię operacji formatujących na tekście wejściowym.
# 1. Usuwa puste tagi, czyli te, które są puste lub zawierają tylko białe znaki (np. " []" lub " [ ]").
# 2. Usuwa nadmiarowe spacje, zamieniając wiele spacji na jedną.
# 3. Usuwa spacje na początku każdej linii.
# Wynikiem działania tej funkcji jest tekstu o uproszczonym i bardziej jednolitym formacie.
additional_formatting() {
    sed 's/ \[\]//g' | sed 's/ \[\s*\]//g' | sed -r 's/  +/ /g' | sed 's/^ *//'
}

# Funkcja process_tags
# Ta funkcja przetwarza tagi w komunikatach commitów, wykonując dwie operacje:
# 1. Wywołuje funkcję extract_and_format_tags do wyodrębnienia tagów JIRA/GitHub i formatowania ich.
# 2. Stosuje dodatkowe formatowanie za pomocą funkcji additional_formatting, aby uporządkować tekst.
process_tags() {
    extract_and_format_tags | additional_formatting
}

# Funkcja add_bullets
# Ta funkcja dodaje gwiazdki (*) na początku każdej linii tekstu.
add_bullets() {
    sed "s|^|*   |"
}

# Funkcja add_jira_links
# Ta funkcja dodaje hiperlinki do identyfikatorów JIRA w komunikatach commitów.
# 1. Szuka wzorców odpowiadających identyfikatorom JIRA (np. ABC-123).
# 2. Zamienia znalezione identyfikatory w linki prowadzące do odpowiednich zadań w JIRA.
add_jira_links() {
    perl -pe 's/\[([A-Z]+-[0-9]+)\]/\[$1\]('"$ESCAPED_JIRA_BASE_URL"'\/$1)/g'
}

# Funkcja add_github_links
# Ta funkcja dodaje hiperlinki do numerów issue w GitHub w komunikatach commitów.
# 1. Szuka wzorców odpowiadających numerom issue (np. #123).
# 2. Zamienia znalezione numery issue w linki prowadzące do odpowiednich issue na GitHub.
add_github_links() {
    sed -r 's|\(#([0-9]+)\)|\[(#\1)\]('"$BASE_URL"'/-/issues/\1)|g'
}

# Funkcja remove_unnecessary_backslashes
# Ta funkcja usuwa niepotrzebne backslashe przed nawiasami kwadratowymi w tekście.
remove_unnecessary_backslashes() {
    sed -E 's/ +\\\[/ \\\[/'
}

# Funkcja configure_git
# Ta funkcja konfiguruje skrypt do pracy z repozytorium git, automatycznie określając ważne informacje.
# Wyciąga dane z konfiguracji git, takie jak URL zdalnego repozytorium, i konfiguruje odpowiednie zmienne.
configure_git() {
    # Pobierz URL zdalnego repozytorium (np. origin) z konfiguracji git.
    remote_url=$(git config --get remote.origin.url)

    # Rozpoznaj, z którym serwisem hostingowym git mamy do czynienia (np. GitLab, GitHub).
    if [[ $remote_url == *"gitlab.com"* ]]; then
        BASE_URL="https://gitlab.com/"
        ISSUE_PREFIX="/-/issues/"
        MR_PREFIX="/-/merge_requests/"
    elif [[ $remote_url == *"github.com"* ]]; then
        BASE_URL="https://github.com/"
        ISSUE_PREFIX="/issues/"
        MR_PREFIX="/pull/"
    else
        echo "Unsupported git hosting service."
        exit 1
    fi

    # Wyodrębnij ścieżkę URL dla obu formatów: HTTPS i SSH.
    if [[ $remote_url =~ https?://[^/]+/(.+) ]]; then
        # Format HTTPS
        url_path=${BASH_REMATCH[1]}
    elif [[ $remote_url =~ git@[^:]+:(.+) ]]; then
        # Format SSH
        url_path=${BASH_REMATCH[1]}
    else
        echo "Failed to extract project path from URL."
        exit 1
    fi

    # Usuń .git z końca URL, jeśli jest obecny.
    url_path=${url_path%.git}

    # Skonstruuj pełny adres URL bazowy.
    BASE_URL="${BASE_URL}${url_path}"
}

# Utworzenie pliku CHANGELOG.md
generate_changelog_file() {
    echo "Generating CHANGELOG.md..."
    > CHANGELOG.md
}

# Funkcja fetch_git_tags
# Ta funkcja pobiera wszystkie tagi z repozytorium git i sortuje je w porządku malejącym.
fetch_git_tags() {
    # Pobiera tagi z zdalnego repozytorium
    if [ $FETCH_TAGS == true ]; then
        echo "git fetch --tags..."
        git fetch --tags
    fi

    echo "Przetwarzanie tagów..."

    # Pobiera najnowszy tag
    latest_tag=$(git tag -l | sort -Vr | head -n 1)

    # Deklaruje tablicę do przechowywania nowych tagów
    declare -a new_tags
    declare -a combined_tags

    # Wywołuje git log z najnowszym tagiem i przetwarza wynik
    while read line; do
        # Wyciąga wszystkie tagi z linii
        tags_line=$(echo $line | grep -o 'tag: [^, )]*' | cut -d ' ' -f 2)

        # Sprawdza, czy istnieją jakieś tagi
        if [[ ! -z "$tags_line" ]]; then
            # Łączy tagi znakiem '_'
            combined_tag=$(echo $tags_line | tr ' ' '_')

            # Dodaje zgrupowane tagi do tablicy combined_tags
            combined_tags+=("$combined_tag")

            # Dodaje tylko pierwszy tag do tablicy new_tags
            first_tag=$(echo $tags_line | awk '{print $1}')
            new_tags+=("$first_tag")
        fi
    done < <(git log $latest_tag --pretty=oneline --decorate=short)

    # Eliminuje duplikaty i sortuje obie tablice
    readarray -t tags < <(printf '%s\n' "${new_tags[@]}" | sort -u -Vr)
    readarray -t display_tags < <(printf '%s\n' "${combined_tags[@]}" | sort -u -Vr)
}

# Funkcja extract_and_format_date
# Ta funkcja wyodrębnia i formatuje datę dla danego tagu git.
# Przetwarza surowe dane o dacie tagu i konwertuje je na bardziej czytelny format.
# 1. Sprawdza, czy surowa data tagu jest w skomplikowanym formacie (zawiera słowo 'tag').
# 2. Wyodrębnia datę z surowych danych i konwertuje ją na format DD.MM.YYYY.
extract_and_format_date() {
    local tag_raw_date=$1
    local tag_date=""
    local formatted_tag_date=""

    if [[ $tag_raw_date == tag* ]]; then # Jeżeli skomplikowana odpowiedź, wyodrębnij datę tagu
        tag_date=$(echo "$tag_raw_date" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}' | head -1)
    else
        tag_date=$tag_raw_date # Jeżeli prosta odpowiedź, użyj całości
    fi

    formatted_tag_date=$(date -d "$tag_date" +'%d.%m.%Y')
    echo $formatted_tag_date
}

# Funkcja extract_tag_author
# Ta funkcja wyodrębnia autora danego tagu git.
# 1. Sprawdza, czy informacje o tagu są w skomplikowanym formacie (zawierają 'tag').
# 2. W takim przypadku, wyodrębnia nazwę autora tagu z tych danych.
# 3. W przeciwnym razie, używa surowych danych jako nazwy autora.
extract_tag_author() {
    local tag=$1
    local tag_output=$(git show $tag --format=%an --no-patch)
    local tag_author=""

    # Wyodrębnij autora tagu
    if [[ $tag_output == tag* ]]; then # Jeżeli skomplikowana odpowiedź, wyodrębnij autora tagu
        tag_author=$(git show $tag --format=fuller --no-patch | grep 'Tagger:' | sed 's/Tagger: //' | sed -E 's/ <.*//' | sed 's/^[ \t]*//')
    else
        tag_author=$tag_output # Jeżeli prosta odpowiedź, użyj całości
    fi

    echo $tag_author
}

# Funkcja format_commit_tags
# Ta funkcja formatuje linię tekstu zawierającą hash commitu i wiadomość commitu.
# 1. Dla każdej linii tekstu, wyodrębnia hash commitu i resztę wiadomości.
# 2. W zależności od wartości zmiennej COMMIT_LINK_END_LINE, hash commitu jest umieszczany na początku lub na końcu linii.
# 3. Wypisuje sformatowaną linię z hashem commitu na odpowiednim miejscu.
format_commit_tags() {
    if [ "$COMMIT_LINK_END_LINE" = true ]; then
        while read -r line; do
            # Usuń hash z początku i zapisz go
            local hash=$(echo "$line" | awk '{print $1}')
            local message=$(echo "$line" | cut -d ' ' -f 2-)

            # Wypisz najpierw wiadomość, a na końcu hash
            echo "$message ($hash)"
        done
    else
        while read -r line; do
            local hash=$(echo "$line" | awk '{print $1}')
            local message=$(echo "$line" | cut -d ' ' -f 2-)

            # Wypisz najpierw hash, a na końcu wiadomość
            echo "($hash) $message"
        done
    fi
}

# Funkcja format_commit_hash
# Ta funkcja formatuje linię tekstu zawierającą pełny hash commitu, przycinając go do pierwszych 7 znaków.
# 1. Dla każdej linii tekstu, wyodrębnia i skraca hash commitu do 7 znaków.
# 2. Wypisuje sformatowaną linię z krótkim hashem commitu i oryginalną wiadomością.
format_commit_hash() {
    awk '{ print "[" substr($1, 1, 7) "] " substr($0, length($1) + 2) }'
}

# Funkcja add_commit_links
# Ta funkcja dodaje linki do commitów na podstawie krótkiego hasha commitu.
# 1. Przechodzi przez każdą linię tekstu.
# 2. Zastępuje krótki hash commitu hiperłączem do pełnego commitu na podstawie dostarczonego BASE_URL.
# 3. Wypisuje sformatowaną linię z linkami do commitów.
add_commit_links() {
    perl -pe 's/\[([a-f0-9]{7})\]/\[$1\]('"${BASE_URL//\//\\/}"'\/-\/commit\/\1)/g'
}

process_commits() {
    local range=$1
    local commits

    # Pobieranie logów commitów
    if [ "$COMMIT_HASHES" = true ]; then
        commits=$(git log --pretty=format:"%H %s" $range)
    else
        commits=$(git log --pretty=format:"%s" $range)
    fi

    # Dodawanie prefixu 'other', jeśli nie używamy ALL_COMMITS
    if [ "$ALL_COMMITS" != true ]; then
        commits=$(echo "$commits" | add_other_prefix | filter_commits | format_commits)
    fi

    # Formatowanie commitów
    commits=$(echo "$commits" \
        | trim_spaces \
        | highlight_identifiers \
        | process_tags)
        
    # Usuwanie wszystkich prefixów jeśli PREFIX jest ustawione na false
    if [ "$PREFIX" = false ]; then
        commits=$(echo "$commits" | remove_prefixes)
    fi
        
    # Dodawanie linków do commitów, jeśli COMMIT_HASHES jest ustawione na true
    if [ "$COMMIT_HASHES" = true ]; then
        commits=$(echo "$commits" \
            | format_commit_hash \
            | format_commit_tags \
            | add_commit_links)
    fi    
    

    commits=$(echo "$commits" | add_jira_links)

    if [ "$GIT_ISSUE_LINK" = true ]; then
        commits=$(echo "$commits" | add_github_links)
    fi
    
    # Dodatkowe formatowanie i dodawanie bulletów
    commits=$(echo "$commits" \
        | remove_unnecessary_backslashes \
        | trim_spaces \
        | add_bullets)

    echo "$commits"
}
        
# Przetwarza informacje o tagach
process_tag_information() {
    local tag=$1
    local next_tag=$2
    local display_tag=${3//_/ }
    local tag_date_raw=$(git show $tag --format=%ai --no-patch)
    local formatted_tag_date=$(extract_and_format_date "$tag_date_raw")
    local tag_author=$(extract_tag_author $tag)
    local compare_url="${BASE_URL}/compare/${next_tag}...${tag}"

    echo -e "### [$display_tag]($compare_url) - $tag_author ($formatted_tag_date)\n" >> CHANGELOG.md
    local commits=$(process_commits "$next_tag..$tag")

    if [ -n "$commits" ]; then
        echo "$commits" >> CHANGELOG.md
    else
        echo "*   No significant changes" >> CHANGELOG.md
    fi

    echo "" >> CHANGELOG.md
}

# Przetwarza informacje o ostatnim tagu
handle_last_tag() {
    local last_tag=$1
    local display_tag=${2//_/ }
    local tag_date_raw=$(git show $last_tag --format=%ai --no-patch)
    local formatted_tag_date=$(extract_and_format_date "$tag_date_raw")
    local tag_author=$(extract_tag_author $last_tag)

    echo -e "### $display_tag - $tag_author ($formatted_tag_date)\n" >> CHANGELOG.md
    local commits=$(process_commits "$last_tag")

    if [ -n "$commits" ]; then
        echo "$commits" >> CHANGELOG.md
    else
        echo "*   No significant changes" >> CHANGELOG.md
    fi
}

main() {
    echo "Sprawdzanie konfiguracji gita"
    configure_git # Konfiguracja gita
    generate_changelog_file # Generowanie pliku CHANGELOG.md
    fetch_git_tags # Pobieranie tagów gita
	
    index=0
    total_tags=${#tags[@]}

    # Przetwarzanie tagów
    while [ $index -lt $((total_tags-1)) ]; do
        tag=${tags[$index]}
        next_tag=${tags[$((index+1))]}
        display_tag=${display_tags[$index]}
        echo "Przetwarzanie commitów $next_tag...$tag dla tagu $display_tag"
        process_tag_information $tag $next_tag $display_tag
        index=$((index+1))
    done

    # Przetwarzanie ostatniego tagu
    echo "Przetwarzanie commitów ostatniego tagu ${display_tags[-1]}"
    handle_last_tag ${tags[-1]} ${display_tags[-1]}
    echo "CHANGELOG.md generated."
}

main
