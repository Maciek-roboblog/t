# Formaty danych dla LLaMA-Factory

## Spis tresci

1. [Wprowadzenie](#wprowadzenie)
2. [Format Alpaca](#format-alpaca)
3. [Format ShareGPT](#format-sharegpt)
4. [Inne formaty](#inne-formaty)
5. [Rejestracja datasetu](#rejestracja-datasetu)
6. [Przygotowanie danych](#przygotowanie-danych)
7. [Walidacja danych](#walidacja-danych)
8. [Dobre praktyki](#dobre-praktyki)

---

## Wprowadzenie

### Wspierane formaty

LLaMA-Factory wspiera wiele formatow danych:

| Format | Uzycie | Zlozonosc |
|--------|--------|-----------|
| **Alpaca** | Instrukcje Q&A | Prosty |
| **ShareGPT** | Konwersacje multi-turn | Sredni |
| **OpenAI** | Chat completions | Sredni |
| **Pretraining** | Raw text | Prosty |

### Wybor formatu

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     WYBOR FORMATU DANYCH                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Czy masz konwersacje (wiele tur)?                                     │
│   │                                                                      │
│   ├── NIE → Format ALPACA                                               │
│   │         (pojedyncze pytania/odpowiedzi)                             │
│   │                                                                      │
│   └── TAK → Format SHAREGPT                                             │
│             (konwersacje z wieloma wiadomosciami)                       │
│                                                                          │
│   Czy masz system prompt?                                               │
│   │                                                                      │
│   ├── TAK → Dodaj pole "system" (Alpaca) lub role "system" (ShareGPT)  │
│   │                                                                      │
│   └── NIE → Pomiń pole system                                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Format Alpaca

### Podstawowa struktura

Format Alpaca to najprostszy format dla instrukcji:

```json
[
  {
    "instruction": "Pytanie lub polecenie dla modelu",
    "input": "Opcjonalny kontekst lub dane wejsciowe",
    "output": "Oczekiwana odpowiedz modelu"
  }
]
```

### Przyklady

#### Proste Q&A (bez input)

```json
[
  {
    "instruction": "Co to jest fotosynteza?",
    "input": "",
    "output": "Fotosynteza to proces, w ktorym rosliny przeksztalcaja energie swietlna w energie chemiczna. Wykorzystuja dwutlenek wegla z powietrza i wode z gleby, produkujac glukoze i tlen jako produkt uboczny."
  },
  {
    "instruction": "Wymien trzy najwieksze planety w Ukladzie Slonecznym.",
    "input": "",
    "output": "Trzy najwieksze planety w Ukladzie Slonecznym to: 1) Jowisz - najwieksza planeta gazowa, 2) Saturn - znany z pierscieniow, 3) Uran - planeta lodowa."
  }
]
```

#### Z kontekstem (z input)

```json
[
  {
    "instruction": "Stresci ponizszy tekst w jednym zdaniu.",
    "input": "Sztuczna inteligencja (AI) to dziedzina informatyki zajmujaca sie tworzeniem systemow zdolnych do wykonywania zadan wymagajacych ludzkiej inteligencji. Obejmuje to uczenie maszynowe, przetwarzanie jezyka naturalnego, rozpoznawanie obrazow i wiele innych obszarow. AI znajduje zastosowanie w medycynie, finansach, transporcie i wielu innych branżach.",
    "input": "Sztuczna inteligencja to dziedzina informatyki tworząca systemy wykonujące zadania wymagające ludzkiej inteligencji, z zastosowaniami w medycynie, finansach i transporcie."
  },
  {
    "instruction": "Przetlumacz na angielski:",
    "input": "Dzien dobry, jak sie masz?",
    "output": "Good morning, how are you?"
  }
]
```

#### Z system prompt

```json
[
  {
    "instruction": "Odpowiedz na pytanie klienta.",
    "input": "Ile kosztuje dostawa?",
    "output": "Dostawa standardowa kosztuje 15 zl i trwa 3-5 dni roboczych. Dostawa ekspresowa kosztuje 25 zl i dociera nastepnego dnia roboczego. Przy zamowieniach powyzej 200 zl dostawa standardowa jest bezplatna.",
    "system": "Jestes asystentem obslugi klienta sklepu internetowego. Odpowiadaj uprzejmie i rzeczowo."
  }
]
```

### Pelna specyfikacja Alpaca

```json
{
  "instruction": "string (wymagane) - Glowne polecenie/pytanie",
  "input": "string (opcjonalne) - Dodatkowy kontekst",
  "output": "string (wymagane) - Oczekiwana odpowiedz",
  "system": "string (opcjonalne) - System prompt",
  "history": "array (opcjonalne) - Historia konwersacji"
}
```

---

## Format ShareGPT

### Podstawowa struktura

Format ShareGPT jest idealny dla konwersacji:

```json
[
  {
    "conversations": [
      {"from": "human", "value": "Wiadomosc uzytkownika"},
      {"from": "gpt", "value": "Odpowiedz asystenta"},
      {"from": "human", "value": "Kolejna wiadomosc"},
      {"from": "gpt", "value": "Kolejna odpowiedz"}
    ]
  }
]
```

### Role

| Rola | Opis | Aliasy |
|------|------|--------|
| `human` | Wiadomosc uzytkownika | `user` |
| `gpt` | Odpowiedz asystenta | `assistant` |
| `system` | System prompt | - |

### Przyklady

#### Prosta konwersacja

```json
[
  {
    "conversations": [
      {
        "from": "human",
        "value": "Czesc! Mozesz mi pomoc z programowaniem?"
      },
      {
        "from": "gpt",
        "value": "Czesc! Oczywiscie, chetnie pomoże. W jakim języku programujesz i z czym masz problem?"
      },
      {
        "from": "human",
        "value": "Ucze sie Pythona i nie rozumiem, czym jest lista."
      },
      {
        "from": "gpt",
        "value": "Lista w Pythonie to struktura danych, ktora przechowuje wiele elementow w okreslonej kolejnosci. Tworzy sie ja uzywajac nawiasow kwadratowych:\n\n```python\nfruity = ['jablko', 'banan', 'pomarancza']\nnumbers = [1, 2, 3, 4, 5]\nmixed = [1, 'tekst', 3.14, True]\n```\n\nListy sa:\n- Indeksowane od 0 (pierwszy element to `lista[0]`)\n- Zmienne (mozna dodawac/usuwac elementy)\n- Mogą przechowywac rozne typy danych\n\nCzy chcesz, zebym pokazal wiecej przykladow?"
      }
    ]
  }
]
```

#### Z system prompt

```json
[
  {
    "conversations": [
      {
        "from": "system",
        "value": "Jestes ekspertem od Python i uczysz poczatkujacych. Tlumaczysz koncepcje prostym jezykiem z przykladami kodu."
      },
      {
        "from": "human",
        "value": "Co to jest funkcja?"
      },
      {
        "from": "gpt",
        "value": "Funkcja to blok kodu, ktory wykonuje okreslone zadanie. Mozesz ja wywolac wielokrotnie zamiast powtarzac ten sam kod.\n\nPrzyklad:\n```python\ndef przywitaj(imie):\n    return f'Czesc, {imie}!'\n\nprint(przywitaj('Anna'))  # Wypisze: Czesc, Anna!\nprint(przywitaj('Jan'))   # Wypisze: Czesc, Jan!\n```\n\nFunkcja `przywitaj` przyjmuje jeden argument (imie) i zwraca powitanie."
      }
    ]
  }
]
```

#### Dluższa konwersacja

```json
[
  {
    "conversations": [
      {
        "from": "system",
        "value": "Jestes pomocnym asystentem kulinarnym."
      },
      {
        "from": "human",
        "value": "Chce upiec ciasto czekoladowe. Masz jakis przepis?"
      },
      {
        "from": "gpt",
        "value": "Oczywiscie! Oto prosty przepis na ciasto czekoladowe:\n\n**Skladniki:**\n- 200g maki\n- 200g cukru\n- 50g kakao\n- 2 jajka\n- 100ml oleju\n- 200ml mleka\n- 1 lyzeczka proszku do pieczenia\n\n**Przygotowanie:**\n1. Rozgrzej piekarnik do 180°C\n2. Wymieszaj suche skladniki\n3. Dodaj jajka, olej i mleko\n4. Piecz 35-40 minut\n\nChcesz, zebym powiedzial wiecej o polewa?"
      },
      {
        "from": "human",
        "value": "Tak, jaka polewa bedzie najlepsza?"
      },
      {
        "from": "gpt",
        "value": "Polecam klasyczna polewa czekoladowa:\n\n**Skladniki:**\n- 100g gorzkiej czekolady\n- 50g masla\n- 2 lyzki smietanki 30%\n\n**Przygotowanie:**\n1. Rozlop czekolade z maslem w kapieli wodnej\n2. Dodaj smietanke i wymieszaj\n3. Polej jeszcze cieple ciasto\n4. Odstaw do zastygnięcia\n\nAlternatywnie mozesz uzyc ganache (polowa czekolady, polowa gorącej smietanki) dla bardziej kremowej konsystencji."
      }
    ]
  }
]
```

### Pelna specyfikacja ShareGPT

```json
{
  "conversations": [
    {
      "from": "string (wymagane) - human/gpt/system",
      "value": "string (wymagane) - Tresc wiadomosci"
    }
  ],
  "system": "string (opcjonalne) - Alternatywnie system prompt",
  "tools": "string (opcjonalne) - Definicje narzedzi dla function calling"
}
```

---

## Inne formaty

### Format OpenAI

Kompatybilny z OpenAI Chat API:

```json
[
  {
    "messages": [
      {"role": "system", "content": "Jestes pomocnym asystentem."},
      {"role": "user", "content": "Czesc!"},
      {"role": "assistant", "content": "Czesc! Jak moge pomoc?"}
    ]
  }
]
```

### Format pretraining

Dla treningu od podstaw (continued pretraining):

```json
[
  {"text": "Pierwszy dokument do treningu..."},
  {"text": "Drugi dokument..."},
  {"text": "Trzeci dokument..."}
]
```

### Format preference (DPO/RLHF)

Dla treningu z preferencjami:

```json
[
  {
    "instruction": "Napisz wiersz o wiośnie.",
    "input": "",
    "chosen": "Wiosna budzi sie ze snu,\nKwiaty kwitna w kazdym dniu,\nPtaki spiewaja wesolo,\nSwiat jest piekny dokola.",
    "rejected": "Wiosna jest ladna. Kwiaty sa. Ptaki tez."
  }
]
```

---

## Rejestracja datasetu

### Lokalizacja

Datasety musza byc zarejestrowane w pliku `dataset_info.json` w LLaMA-Factory:

```
LLaMA-Factory/
└── data/
    ├── dataset_info.json  # Rejestracja datasetow
    ├── alpaca_en.json     # Przykladowy dataset
    └── my_dataset.json    # Twoj dataset
```

### Format rejestracji

```json
{
  "my_dataset": {
    "file_name": "my_dataset.json",
    "columns": {
      "prompt": "instruction",
      "query": "input",
      "response": "output",
      "system": "system"
    }
  },
  "my_sharegpt_dataset": {
    "file_name": "my_conversations.json",
    "formatting": "sharegpt",
    "columns": {
      "messages": "conversations"
    },
    "tags": {
      "role_tag": "from",
      "content_tag": "value",
      "user_tag": "human",
      "assistant_tag": "gpt",
      "system_tag": "system"
    }
  }
}
```

### Przyklad kompletnej rejestracji

```json
{
  "polish_qa": {
    "file_name": "polish_qa.json",
    "formatting": "alpaca",
    "columns": {
      "prompt": "instruction",
      "query": "input",
      "response": "output"
    }
  },
  "customer_service": {
    "file_name": "customer_service.json",
    "formatting": "sharegpt",
    "columns": {
      "messages": "conversations"
    },
    "tags": {
      "role_tag": "from",
      "content_tag": "value",
      "user_tag": "human",
      "assistant_tag": "gpt",
      "system_tag": "system"
    }
  },
  "code_instructions": {
    "file_name": "code_data.json",
    "formatting": "alpaca",
    "columns": {
      "prompt": "instruction",
      "query": "input",
      "response": "output",
      "system": "system"
    }
  }
}
```

### Uzycie w treningu

```yaml
# train.yaml
dataset: polish_qa,customer_service  # Mozna laczyc datasety
```

---

## Przygotowanie danych

### Proces przygotowania

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    PROCES PRZYGOTOWANIA DANYCH                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   1. ZBIERANIE                                                          │
│      └── Surowe dane (CSV, TXT, bazy danych, API)                      │
│                                                                          │
│   2. CZYSZCZENIE                                                        │
│      ├── Usuwanie duplikatow                                           │
│      ├── Usuwanie pustych/blednych rekordow                            │
│      ├── Normalizacja tekstu                                           │
│      └── Anonimizacja danych wrazliwych                                │
│                                                                          │
│   3. FORMATOWANIE                                                       │
│      └── Konwersja do formatu Alpaca/ShareGPT                          │
│                                                                          │
│   4. WALIDACJA                                                          │
│      ├── Sprawdzenie struktury JSON                                    │
│      ├── Sprawdzenie wymaganych pol                                    │
│      └── Statystyki dlugosci                                           │
│                                                                          │
│   5. PODZIAL                                                            │
│      ├── Train: 80-90%                                                 │
│      ├── Validation: 10-15%                                            │
│      └── Test: 5-10%                                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Skrypt konwersji (CSV → Alpaca)

```python
#!/usr/bin/env python3
"""Konwersja CSV do formatu Alpaca"""

import csv
import json
import sys

def csv_to_alpaca(input_file, output_file):
    data = []

    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            item = {
                "instruction": row.get('pytanie', row.get('question', '')),
                "input": row.get('kontekst', row.get('context', '')),
                "output": row.get('odpowiedz', row.get('answer', ''))
            }

            # Dodaj system prompt jesli istnieje
            if 'system' in row and row['system']:
                item['system'] = row['system']

            # Walidacja - nie dodawaj pustych rekordow
            if item['instruction'] and item['output']:
                data.append(item)

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"Zapisano {len(data)} rekordow do {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Uzycie: python csv_to_alpaca.py input.csv output.json")
        sys.exit(1)

    csv_to_alpaca(sys.argv[1], sys.argv[2])
```

### Skrypt konwersji (chat logs → ShareGPT)

```python
#!/usr/bin/env python3
"""Konwersja logow czatu do formatu ShareGPT"""

import json
import sys
import re

def parse_chat_log(log_text):
    """Parsuje tekst czatu do listy wiadomosci"""
    conversations = []
    current_conv = []

    lines = log_text.strip().split('\n')

    for line in lines:
        # Pattern: [USER] tekst lub [ASSISTANT] tekst
        user_match = re.match(r'\[USER\]\s*(.+)', line, re.IGNORECASE)
        assistant_match = re.match(r'\[ASSISTANT\]\s*(.+)', line, re.IGNORECASE)
        separator_match = re.match(r'---+', line)

        if user_match:
            current_conv.append({
                "from": "human",
                "value": user_match.group(1).strip()
            })
        elif assistant_match:
            current_conv.append({
                "from": "gpt",
                "value": assistant_match.group(1).strip()
            })
        elif separator_match and current_conv:
            if len(current_conv) >= 2:  # Min. 1 user + 1 assistant
                conversations.append({"conversations": current_conv})
            current_conv = []

    # Ostatnia konwersacja
    if current_conv and len(current_conv) >= 2:
        conversations.append({"conversations": current_conv})

    return conversations

def convert_chat_logs(input_file, output_file):
    with open(input_file, 'r', encoding='utf-8') as f:
        log_text = f.read()

    data = parse_chat_log(log_text)

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"Zapisano {len(data)} konwersacji do {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Uzycie: python chat_to_sharegpt.py input.txt output.json")
        sys.exit(1)

    convert_chat_logs(sys.argv[1], sys.argv[2])
```

---

## Walidacja danych

### Skrypt walidacji

```python
#!/usr/bin/env python3
"""Walidacja datasetu LLaMA-Factory"""

import json
import sys
from collections import Counter

def validate_alpaca(data):
    """Walidacja formatu Alpaca"""
    errors = []
    warnings = []
    stats = {
        'total': len(data),
        'with_input': 0,
        'with_system': 0,
        'instruction_lengths': [],
        'output_lengths': []
    }

    for i, item in enumerate(data):
        # Sprawdz wymagane pola
        if 'instruction' not in item:
            errors.append(f"Rekord {i}: Brak pola 'instruction'")
        elif not item['instruction'].strip():
            warnings.append(f"Rekord {i}: Puste pole 'instruction'")
        else:
            stats['instruction_lengths'].append(len(item['instruction']))

        if 'output' not in item:
            errors.append(f"Rekord {i}: Brak pola 'output'")
        elif not item['output'].strip():
            warnings.append(f"Rekord {i}: Puste pole 'output'")
        else:
            stats['output_lengths'].append(len(item['output']))

        # Sprawdz opcjonalne pola
        if item.get('input', '').strip():
            stats['with_input'] += 1

        if item.get('system', '').strip():
            stats['with_system'] += 1

    return errors, warnings, stats

def validate_sharegpt(data):
    """Walidacja formatu ShareGPT"""
    errors = []
    warnings = []
    stats = {
        'total': len(data),
        'total_messages': 0,
        'avg_turns': 0,
        'with_system': 0,
        'roles': Counter()
    }

    turn_counts = []

    for i, item in enumerate(data):
        if 'conversations' not in item:
            errors.append(f"Rekord {i}: Brak pola 'conversations'")
            continue

        convs = item['conversations']
        if not convs:
            warnings.append(f"Rekord {i}: Pusta lista conversations")
            continue

        turn_counts.append(len(convs))
        stats['total_messages'] += len(convs)

        has_system = False
        for j, msg in enumerate(convs):
            if 'from' not in msg:
                errors.append(f"Rekord {i}, wiadomosc {j}: Brak pola 'from'")
            else:
                stats['roles'][msg['from']] += 1
                if msg['from'] == 'system':
                    has_system = True

            if 'value' not in msg:
                errors.append(f"Rekord {i}, wiadomosc {j}: Brak pola 'value'")
            elif not msg['value'].strip():
                warnings.append(f"Rekord {i}, wiadomosc {j}: Pusta wiadomosc")

        if has_system:
            stats['with_system'] += 1

    if turn_counts:
        stats['avg_turns'] = sum(turn_counts) / len(turn_counts)

    return errors, warnings, stats

def detect_format(data):
    """Wykrywa format datasetu"""
    if not data:
        return None

    sample = data[0]
    if 'conversations' in sample:
        return 'sharegpt'
    elif 'instruction' in sample:
        return 'alpaca'
    elif 'messages' in sample:
        return 'openai'
    elif 'text' in sample:
        return 'pretraining'
    else:
        return 'unknown'

def main(input_file):
    print(f"\n{'='*60}")
    print(f"Walidacja: {input_file}")
    print('='*60)

    # Wczytaj dane
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"\nBLAD: Nieprawidlowy JSON - {e}")
        return 1
    except FileNotFoundError:
        print(f"\nBLAD: Plik nie istnieje")
        return 1

    if not isinstance(data, list):
        print("\nBLAD: Dane musza byc lista (array)")
        return 1

    # Wykryj format
    fmt = detect_format(data)
    print(f"\nWykryty format: {fmt}")

    # Walidacja
    if fmt == 'alpaca':
        errors, warnings, stats = validate_alpaca(data)
    elif fmt == 'sharegpt':
        errors, warnings, stats = validate_sharegpt(data)
    else:
        print("Nieobslugiwany format")
        return 1

    # Wyswietl wyniki
    print(f"\n--- STATYSTYKI ---")
    for key, value in stats.items():
        if isinstance(value, list):
            if value:
                print(f"  {key}: min={min(value)}, max={max(value)}, avg={sum(value)/len(value):.1f}")
        elif isinstance(value, Counter):
            print(f"  {key}: {dict(value)}")
        else:
            print(f"  {key}: {value}")

    print(f"\n--- BLEDY ({len(errors)}) ---")
    for err in errors[:10]:
        print(f"  [ERROR] {err}")
    if len(errors) > 10:
        print(f"  ... i {len(errors)-10} wiecej")

    print(f"\n--- OSTRZEZENIA ({len(warnings)}) ---")
    for warn in warnings[:10]:
        print(f"  [WARN] {warn}")
    if len(warnings) > 10:
        print(f"  ... i {len(warnings)-10} wiecej")

    # Podsumowanie
    print(f"\n--- PODSUMOWANIE ---")
    if errors:
        print(f"  NIEPOPRAWNY - {len(errors)} bledow")
        return 1
    elif warnings:
        print(f"  POPRAWNY (z ostrzezeniami) - {len(warnings)} ostrzezen")
        return 0
    else:
        print("  POPRAWNY - brak problemow")
        return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Uzycie: python validate_dataset.py dataset.json")
        sys.exit(1)

    sys.exit(main(sys.argv[1]))
```

### Uzycie walidatora

```bash
# Walidacja datasetu
python validate_dataset.py my_dataset.json

# Przykladowy output:
# ============================================================
# Walidacja: my_dataset.json
# ============================================================
#
# Wykryty format: alpaca
#
# --- STATYSTYKI ---
#   total: 1500
#   with_input: 450
#   with_system: 100
#   instruction_lengths: min=10, max=500, avg=85.3
#   output_lengths: min=20, max=2000, avg=350.2
#
# --- BLEDY (0) ---
#
# --- OSTRZEZENIA (3) ---
#   [WARN] Rekord 145: Puste pole 'output'
#   [WARN] Rekord 892: Puste pole 'instruction'
#   [WARN] Rekord 1203: Puste pole 'output'
#
# --- PODSUMOWANIE ---
#   POPRAWNY (z ostrzezeniami) - 3 ostrzezen
```

---

## Dobre praktyki

### Jakosc danych

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DOBRE PRAKTYKI - JAKOSC DANYCH                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   DO:                                                                   │
│   ✓ Usun duplikaty i prawie-duplikaty                                  │
│   ✓ Sprawdz poprawnosc gramatyczna i ortograficzna                     │
│   ✓ Zachowaj spojnosc stylu (formalny/nieformalny)                     │
│   ✓ Uzywaj kompletnych zdan                                            │
│   ✓ Dodawaj kontekst gdy potrzebny                                     │
│   ✓ Balansuj dlugosci odpowiedzi                                       │
│                                                                          │
│   NIE:                                                                  │
│   ✗ Nie wstawiaj danych osobowych (RODO!)                              │
│   ✗ Nie zostawiaj smieci (HTML, specjalne znaki)                       │
│   ✗ Nie uzywaj zbyt krotkich odpowiedzi (<10 slow)                     │
│   ✗ Nie powtarzaj tych samych pytan/odpowiedzi                         │
│   ✗ Nie mieszaj jezykow bez powodu                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Rozmiar datasetu

| Rozmiar | Przyklady | Zastosowanie |
|---------|-----------|--------------|
| Maly | 100-1,000 | Prototypowanie, testy |
| Sredni | 1,000-10,000 | Typowy fine-tuning |
| Duzy | 10,000-100,000 | Zaawansowany fine-tuning |
| Bardzo duzy | 100,000+ | Pre-training, specjalizacja |

**Rekomendacja:** Zacznij od 1,000-5,000 wysokiej jakosci przykladow.

### Dlugosci tekstow

```yaml
# Rekomendowane dlugosci (w tokenach, ~4 znaki = 1 token)

instruction:
  min: 10 tokenow (~40 znakow)
  max: 200 tokenow (~800 znakow)
  optymalnie: 20-100 tokenow

output:
  min: 20 tokenow (~80 znakow)
  max: cutoff_len - instruction_len
  optymalnie: 100-500 tokenow

# Uwaga na cutoff_len w konfiguracji treningu!
cutoff_len: 2048  # instruction + output musi sie zmiescic
```

### Balans kategorii

```python
# Sprawdz balans kategorii w danych
from collections import Counter

# Dla datasetu z kategoriami
categories = [item.get('category', 'unknown') for item in data]
distribution = Counter(categories)

print("Rozklad kategorii:")
for cat, count in distribution.most_common():
    pct = count / len(data) * 100
    print(f"  {cat}: {count} ({pct:.1f}%)")

# Wynik przykladowy:
# qa: 500 (33.3%)
# summary: 400 (26.7%)
# translation: 350 (23.3%)
# code: 250 (16.7%)
```

### Podzial train/val/test

```python
import json
import random

def split_dataset(input_file, train_ratio=0.85, val_ratio=0.10):
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    random.shuffle(data)

    n = len(data)
    train_end = int(n * train_ratio)
    val_end = int(n * (train_ratio + val_ratio))

    train_data = data[:train_end]
    val_data = data[train_end:val_end]
    test_data = data[val_end:]

    # Zapisz
    base_name = input_file.rsplit('.', 1)[0]

    with open(f"{base_name}_train.json", 'w', encoding='utf-8') as f:
        json.dump(train_data, f, ensure_ascii=False, indent=2)

    with open(f"{base_name}_val.json", 'w', encoding='utf-8') as f:
        json.dump(val_data, f, ensure_ascii=False, indent=2)

    with open(f"{base_name}_test.json", 'w', encoding='utf-8') as f:
        json.dump(test_data, f, ensure_ascii=False, indent=2)

    print(f"Train: {len(train_data)}, Val: {len(val_data)}, Test: {len(test_data)}")

# Uzycie
split_dataset("my_dataset.json")
```

---

## Przyklady kompletnych datasetow

### Dataset Q&A po polsku

```json
[
  {
    "instruction": "Odpowiedz na pytanie dotyczace historii Polski.",
    "input": "Kiedy Polska odzyskala niepodleglosc?",
    "output": "Polska odzyskala niepodleglosc 11 listopada 1918 roku, po 123 latach zaborow. Data ta jest obchodzona jako Narodowe Swieto Niepodleglosci. Odzyskanie niepodleglosci bylo mozliwe dzieki zakonczeniu I wojny swiatowej i upadkowi trzech mocarstw zaborczych: Niemiec, Austro-Wegier i Rosji.",
    "system": "Jestes ekspertem od historii Polski. Odpowiadaj rzeczowo i wyczerpujaco."
  },
  {
    "instruction": "Odpowiedz na pytanie dotyczace geografii Polski.",
    "input": "Jaka jest najwyzsza gora w Polsce?",
    "output": "Najwyzsza gora w Polsce to Rysy, o wysokosci 2499 m n.p.m. (szczyt poludniowy-slowacki ma 2503 m). Rysy znajduja sie w Tatrach Wysokich, na granicy polsko-slowackiej. Szczyt jest popularnym celem turystycznym, a wejscie na niego mozliwe jest szlakami z Morskiego Oka lub od strony slowackiej.",
    "system": "Jestes ekspertem od geografii Polski. Odpowiadaj rzeczowo i wyczerpujaco."
  }
]
```

### Dataset obslugi klienta

```json
[
  {
    "conversations": [
      {
        "from": "system",
        "value": "Jestes asystentem obslugi klienta sklepu internetowego TechShop. Pomagasz klientom z zamowieniami, zwrotami i pytaniami o produkty. Badz uprzejmy i pomocny."
      },
      {
        "from": "human",
        "value": "Czesc, chce zwrocic laptop ktory kupilem tydzien temu."
      },
      {
        "from": "gpt",
        "value": "Dzien dobry! Chetnie pomoze z procesem zwrotu laptopa. Czy moglby Pan/Pani podac numer zamowienia? Znajde go w panelu - zaczyna sie od liter TS i ma 8 cyfr."
      },
      {
        "from": "human",
        "value": "Tak, to TS12345678"
      },
      {
        "from": "gpt",
        "value": "Dziekuje! Znalazlem zamowienie TS12345678 - laptop Dell XPS 15. Kupiony 7 dni temu, wiec miesci sie w 14-dniowym okresie na zwrot.\n\nProsze o informacje:\n1. Czy laptop jest w oryginalnym opakowaniu?\n2. Jaki jest powod zwrotu?\n\nPo otrzymaniu tych informacji wyslemy etykiete zwrotna na Pana/Pani email."
      }
    ]
  }
]
```

---

*Dokumentacja formatow danych dla LLaMA-Factory*
