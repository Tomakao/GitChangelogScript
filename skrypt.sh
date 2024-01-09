#!/bin/bash

# Automatycznie określ nazwę użytkownika i nazwę projektu z konfiguracji git
remote_url=$(git config --get remote.origin.url)
if [[ $remote_url == *"gitlab.com"* ]]; then
  BASE_URL="https://gitlab.com/systemy-biletowe-rg/krg/"
  ISSUE_PREFIX="/-/issues/"
  MR_PREFIX="/-/merge_requests/"
elif [[ $remote_url == *"github.com"* ]]; then
  BASE_URL="https://github.com/systemy-biletowe-rg/krg/"
  ISSUE_PREFIX="/issues/"
  MR_PREFIX="/pull/"
else
  echo "Unsupported git hosting service."
  exit 1
fi

# Wyodrębnij nazwę użytkownika i nazwę projektu ze zdalnego adresu URL
if [[ $remote_url =~ .*/(.+)/(.+)\.git ]]; then
  username=${BASH_REMATCH[1]}
  projectname=${BASH_REMATCH[2]}
fi

echo "Generating CHANGELOG.md..."
> CHANGELOG.md

# Pobierz wszystkie tagi, posortuj je odwrotnie i sformatuj wynik
git fetch --tags
tags=($(git tag -l | sort -Vr))

#echo "$tags"

# Zmienna pomocnicza do przechowywania aktualnego indeksu
index=0

# Pobierz liczbę tagów
total_tags=${#tags[@]}

# Iteruj po każdym znaczniku w odwrotnej kolejności, oprócz ostatniego
while [ $index -lt $((total_tags-1)) ]; do
    tag=${tags[$index]}
    next_tag=${tags[$((index+1))]}

    # Uzyskaj datę tagu, autora i porównaj adres URL
    
    tag_date_raw=$(git show $tag --format=%ai --no-patch)

    # Sprawdź, czy pierwszym słowem jest "tag", co oznacza, że tag jest opisany szczegółowo
    if [[ $tag_date_raw == tag* ]]; then
        # Wyodrębnij datę z opisu szczegółowego tagu
        tag_date=$(echo "$tag_date_raw" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}' | head -1)
    else
        # Użyj całego wyniku jako daty dla prostych tagów
        tag_date=$tag_date_raw
    fi

    # Formatuj wyodrębnioną datę
    formatted_tag_date=$(date -d "$tag_date" +'%d.%m.%Y')

    #echo $formatted_tag_date
    
    tag_output=$(git show $tag --format=%an --no-patch)

    if [[ $tag_output == tag* ]]; then
      # Jeśli wynik zaczyna się od „tag”, wyodrębnij nazwę z linii „Tagger:”
	    tag_author=$(git show $tag --format=fuller --no-patch | grep 'Tagger:' | sed 's/Tagger: //' | sed -E 's/ <.*//' | sed 's/^[ \t]*//')
    else
	    # W przeciwnym razie użyj całego wyniku jako nazwę autora
	    tag_author=$tag_output
    fi

    #echo $tag_author

    compare_url="${BASE_URL}${username}/${projectname}/-/compare/${next_tag}...${tag}"

    # Dodaj tag do CHANGELOG.md z linkiem porównawczym
    echo -e "### [$tag]($compare_url) - $tag_author ($formatted_tag_date)\n" >> CHANGELOG.md

    # Uzyskaj listę zmian wprowadzonych w tagu
    raw_commits=$(git log --pretty=format:"%s" $next_tag..$tag)
    
    #echo "$raw_commits"

    # Wyodrębnianie i wyświetlanie commitów z prefixem „fix:”, „feat:” lub „chore:”
    # Dodanie obsługi commitów bez prefixu dla kompatybilności wstecznej.
    # Zostaje dodany do nich prefix "other:" dla odróżnienia po czym jest usuwany.
    commits=$(echo "$raw_commits" \
          | awk -F: '{if (NF>1) print $0; else print "other: "$0;}' \
          | grep -E "fix\(.*\):|feat\(.*\):|chore\(.*\):|fix:|feat:|chore:|other:" \
          | sed -E 's/\b(fix|feat|chore)\(([^)]+)\):([^:]+)/\2: \3/g' \
          | sed -E 's/\b(fix:|feat:|chore:|other:)//g' \
          | sed 's/^ *//' \
          | sed 's/ $//' \
          | sed -E 's/\b([A-Z]+-[0-9]+)\b/[\1]/g' \
          | sed -E 's/\[\[([A-Z]+-[0-9]+)\]\]/[\1]/g' \
          | awk '{
              line = $0; # Zapisz linię do zmiennej
              gsub(/^ +| +$/, "", line); # Przytnij spacje
              tags = "";
              while(match(line, /\[[A-Z]+-[0-9]+\]/)) { # Znajdź tagi
                  tag = substr(line, RSTART, RLENGTH); # Wyodrębnij tagi
                  line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH); # Usuń tagi z linii
                  tags = tags tag " "; # Dodaj tagi do listy tagów
              }
              gsub(/ +$/, "", tags); # Przytnij spacje
              if (tags != "") {
                  print line " \\[" tags "\\]"; # Wypisz linię z tagami
              } else {
                  print line; # Jeśli nie znaleziono tagów, wypisz całą linię
              }
          }' \
          | sed 's/ \[\]//g' \
          | sed 's/ \[\s*\]//g' \
          | sed -r 's/  +/ /g' \
          | sed 's/^ *//' \
          | sed "s|^|*   |" \
          | perl -pe 's/\[([A-Z]+-[0-9]+)\]/\[$1](https:\/\/rg-plus.atlassian.net\/browse\/$1)/g' \
          | sed -r 's/\(#([0-9]+)\)/\[(#\1)\](https:\/\/gitlab.com\/systemy-biletowe-rg\/krg\/'"$username"'\/'"$projectname"'\/-\/issues\/\1)/g' \
          | sed -E 's/ +\\\[/ \\\[/' )


    # Powtórz każde zatwierdzenie osobno, upewniając się, że nie ma dodatkowych znaków nowej linii
    if [ -n "$commits" ]; then
        echo "$commits" >> CHANGELOG.md
    else
        echo "* No significant changes" >> CHANGELOG.md
    fi

    echo "" >> CHANGELOG.md

    # Przejdź do następnego znacznika
    index=$((index+1))
done


#######################################################
# Obsługuj ostatni tag osobno, bez linku porównawczego
#######################################################

last_tag=${tags[-1]}

# Uzyskaj datę tagu, autora i porównaj adres URL
tag_date_raw=$(git show $last_tag --format=%ai --no-patch)

# Sprawdź, czy pierwszym słowem jest "tag", co oznacza, że tag jest opisany szczegółowo
if [[ $tag_date_raw == tag* ]]; then
    # Wyodrębnij datę z opisu szczegółowego tagu
    tag_date=$(echo "$tag_date_raw" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}' | head -1)
else
    # Użyj całego wyniku jako daty dla prostych tagów
    tag_date=$tag_date_raw
fi

# Formatuj wyodrębnioną datę
formatted_tag_date=$(date -d "$tag_date" +'%d.%m.%Y')

#echo $formatted_tag_date

tag_output=$(git show $last_tag --format=%an --no-patch)

if [[ $tag_output == tag* ]]; then
  # Jeśli pierwszy wynik zaczyna się od „tag”, wyodrębnij nazwę z linii „Tagger:”
  tag_author=$(git show $last_tag --format=fuller --no-patch | grep 'Tagger:' | sed 's/Tagger: //' | sed -E 's/ <.*//' | sed 's/^[ \t]*//')
else
  # W przeciwnym razie użyj całego wyniku jako nazwy autora
  tag_author=$tag_output
fi

#echo $tag_author




echo -e "### $last_tag - $tag_author ($formatted_tag_date)\n" >> CHANGELOG.md

# Uzyskaj listę zmian wprowadzonych w tagu
raw_commits=$(git log --pretty=format:"%s" $last_tag)

# Wyodrębnianie i wyświetlanie commitów z prefixem „fix:”, „feat:” lub „chore:”
# Dodanie obsługi commitów bez prefixu dla kompatybilności wstecznej.
# Zostaje dodany do nich prefix "other:" dla odróżnienia po czym jest usuwany.
commits=$(echo "$raw_commits" \
          | awk -F: '{if (NF>1) print $0; else print "other: "$0;}' \
          | grep -E "fix\(.*\):|feat\(.*\):|chore\(.*\):|fix:|feat:|chore:|other:" \
          | sed -E 's/\b(fix|feat|chore)\(([^)]+)\):([^:]+)/\2: \3/g' \
          | sed -E 's/\b(fix:|feat:|chore:|other:)//g' \
          | sed 's/^ *//' \
          | sed 's/ $//' \
          | sed -E 's/\b([A-Z]+-[0-9]+)\b/[\1]/g' \
          | sed -E 's/\[\[([A-Z]+-[0-9]+)\]\]/[\1]/g' \
          | awk '{
              line = $0; # Zapisz linię do zmiennej
              gsub(/^ +| +$/, "", line); # Przytnij spacje
              tags = "";
              while(match(line, /\[[A-Z]+-[0-9]+\]/)) { # Znajdź tagi
                  tag = substr(line, RSTART, RLENGTH); # Wyodrębnij tagi
                  line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH); # Usuń tagi z linii
                  tags = tags tag " "; # Dodaj tagi do listy tagów
              }
              gsub(/ +$/, "", tags); # Przytnij spacje
              if (tags != "") {
                  print line " \\[" tags "\\]"; # Wypisz linię z tagami
              } else {
                  print line; # Jeśli nie znaleziono tagów, wypisz całą linię
              }
          }' \
          | sed 's/ \[\]//g' \
          | sed 's/ \[\s*\]//g' \
          | sed -r 's/  +/ /g' \
          | sed 's/^ *//' \
          | sed "s|^|*   |" \
          | perl -pe 's/\[([A-Z]+-[0-9]+)\]/\[$1](https:\/\/rg-plus.atlassian.net\/browse\/$1)/g' \
          | sed -r 's/\(#([0-9]+)\)/\[(#\1)\](https:\/\/gitlab.com\/systemy-biletowe-rg\/krg\/'"$username"'\/'"$projectname"'\/-\/issues\/\1)/g' \
          | sed -E 's/ +\\\[/ \\\[/' )


if [ -n "$commits" ]; then
    echo "$commits" >> CHANGELOG.md
else
    echo "* No significant changes" >> CHANGELOG.md
fi

echo "CHANGELOG.md generated."

