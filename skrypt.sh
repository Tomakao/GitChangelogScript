#!/bin/bash

#Definicje
JIRA_BASE_URL="https://rg-plus.atlassian.net/browse"

# Użytkownik może zdefiniować tutaj prefixy, które chce filtrować
PREFIXES=("fix" "feat" "chore")
OTHER_PREFIX="other"

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
    grep -E "($prefixes_regex)\(.*\):|($prefixes_regex):|$OTHER_PREFIX:"
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
    | sed -E "s/\b(($prefixes_regex):||$OTHER_PREFIX:)//g"
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
    awk '{
        line = $0; # Zapisz linię do zmiennej
        gsub(/^ +| +$/, "", line); # Przytnij spacje na początku i końcu
        tags = "";
        while (match(line, /\[[A-Z]+-[0-9]+\]/)) { # Znajdź tagi JIRA/GitHub
            tag = substr(line, RSTART, RLENGTH); # Wyodrębnij tag
            line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH); # Usuń tag z linii
            tags = tags tag " "; # Dodaj tag do listy tagów
        }
        gsub(/ +$/, "", tags); # Przytnij spacje na końcu listy tagów
        if (tags != "") {
            print line " \\[" tags "\\]"; # Wypisz linię z tagami
        } else {
            print line; # Wypisz linię bez tagów
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

    # Wyodrębnij wszystkie składowe URL poza domeną gitlab.com/github.com.
    if [[ $remote_url =~ https?://[^/]+/(.+) ]]; then
        url_path=${BASH_REMATCH[1]}
        url_path=${url_path%.git} # Usuń .git z końca URL, jeśli jest obecny.
        BASE_URL="${BASE_URL}${url_path}"
    else
        echo "Failed to extract project path from URL."
        exit 1
    fi
}

# Utworzenie pliku CHANGELOG.md
generate_changelog_file() {
    echo "Generating CHANGELOG.md..."
    > CHANGELOG.md
}

# Funkcja fetch_git_tags
# Ta funkcja pobiera wszystkie tagi z repozytorium git i sortuje je w porządku malejącym.
fetch_git_tags() {
    git fetch --tags # Pobiera tagi z zdalnego repozytorium
    tags=($(git tag -l | sort -Vr)) # Tworzy tablicę tagów posortowanych wersyjnie (od najnowszego)
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


# Przetwarzaj listę commitów
process_commits() {
    local range=$1
    local commits=$(git log --pretty=format:"%s" $range \
        | add_other_prefix \
        | filter_commits \
        | format_commits \
        | trim_spaces \
        | highlight_identifiers \
        | process_tags \
        | add_bullets \
        | add_jira_links \
        | add_github_links \
        | remove_unnecessary_backslashes)
    echo "$commits"
}

# Przetwarza informacje o tagach
process_tag_information() {
    local tag=$1
    local next_tag=$2
    local tag_date_raw=$(git show $tag --format=%ai --no-patch)
    local formatted_tag_date=$(extract_and_format_date "$tag_date_raw")
    local tag_author=$(extract_tag_author $tag)
    local compare_url="${BASE_URL}/-/compare/${next_tag}...${tag}"
    
    echo $BASE_URL

    echo -e "### [$tag]($compare_url) - $tag_author ($formatted_tag_date)\n" >> CHANGELOG.md
    local commits=$(process_commits "$next_tag..$tag")

    if [ -n "$commits" ]; then
        echo "$commits" >> CHANGELOG.md
    else
        echo "* No significant changes" >> CHANGELOG.md
    fi

    echo "" >> CHANGELOG.md
}

# Przetwarza informacje o ostatnim tagu
handle_last_tag() {
    local last_tag=$1
    local tag_date_raw=$(git show $last_tag --format=%ai --no-patch)
    local formatted_tag_date=$(extract_and_format_date "$tag_date_raw")
    local tag_author=$(extract_tag_author $last_tag)

    echo -e "### $last_tag - $tag_author ($formatted_tag_date)\n" >> CHANGELOG.md
    local commits=$(process_commits "$last_tag")

    if [ -n "$commits" ]; then
        echo "$commits" >> CHANGELOG.md
    else
        echo "* No significant changes" >> CHANGELOG.md
    fi
}

main() {
    configure_git # Konfiguracja gita
    generate_changelog_file # Generowanie pliku CHANGELOG.md
    fetch_git_tags # Pobieranie tagów gita

    index=0
    total_tags=${#tags[@]}

    # Przetwarzanie tagów
    while [ $index -lt $((total_tags-1)) ]; do
        tag=${tags[$index]}
        next_tag=${tags[$((index+1))]}
        process_tag_information $tag $next_tag
        index=$((index+1))
    done

    # Przetwarzanie ostatniego tagu
    handle_last_tag ${tags[-1]}
    echo "CHANGELOG.md generated."
}

main
