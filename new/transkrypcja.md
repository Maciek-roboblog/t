Mówca 1
Segment #1
Sposób, w jaki to jest wystawiane. Czekaj, ja zobaczę w końcu ten, spróbuję to pokazać. Skąd są uwagi brane, skąd modele, bo to dobrze byłoby tą spójność gdzieś tutaj zachować, nie? Od razu też mów, bo to, wiesz, ja będę może challenge'ował coś, co u ciebie jest, a to, co ja przedstawiam, no to ty możesz challenge'ować, tak? Wiesz, w ten sposób.

Mówca 2
Segment #1
Jasne.

Mówca 1
Segment #1
Może jakiś sensowny też wyjdzie ten wynik. Poczekaj, to jeszcze chwilę produkty formacji, dobra.

Mówca 2
Segment #1
Ciekawe, czy znalazłem to, co miałem znaleźć.

Mówca 1
Segment #1
Czy to jest architektura? Ktoś mi tutaj nazwał. Dobra. Jasne. Okej. Dobra, dobra.

Mówca 2
Segment #1
A gdzie to jest?

Mówca 1
Segment #1
Proszę? O, tutaj mi się zrobiło ten, mam te czarno.

Mówca 2
Segment #1
A, to ty szerujesz. Okej, dobra, nie widziałem.

Mówca 1
Segment #1
Tak, tak, tak.

Mówca 2
Segment #1
Model as a service, to tam byłem. Architektura, okej. Ja wszedłem w VLLM-a z automatu, dlatego jakby...

Mówca 1
Segment #1
Teraz tak. W tej chwili na tym klastrze takie dwa namespace'y, w których pracujemy. Na tych klastrach takich w Holandii, bo mamy dwa rodzaje środowisk. Mamy takie bardziej stare, MLOps-owe, gdzie trochę inaczej to wygląda. I tam na przykład mamy takie to całe trenowanie, wiesz, zorganizowane i tak dalej. Natomiast mamy też, to może za chwilę trochę powiem, jak to wygląda. Mamy też środowisko do tej inferencji dla tych modeli, powiedzmy, które zrobiliśmy w ramach FSI, czyli takich bardziej LLM-owych, czy tam powiedzmy tych takich wspierających te rozwiązania, takie typu wyszukiwarka, system programisty. No i tutaj tak. Jest ogólnie, są te model serwery. W większości one są bazują na tym, że mamy taki jeden taki najbardziej generyczny model serwer, no to jest tam oparty na VLLM-ie. I w zasadzie tutaj jakby no i obraz właśnie taki generyczny jakby tego model serwera wykorzystujemy i po prostu przez parametry sterujemy tym, powiedzmy, już tam dostosowaniem do konkretnego modelu. A jeśli chodzi o ten, o wagi, one są pobierane z MLFlow, czyli z MLFlow rejestrujemy modele i z tego tam, powiedzmy, jak serwis startuje, to wciąga tam te wagi do dysku takiego mapowanego w pamięci. Także to dosyć szybko, tam parę sekund to trwa chyba tam, żeby tam załadować taki model z tego MLFlow'a. Dlaczego MLFlow? No tutaj to może jest trochę taki na wyrost, nie? Ale generalnie w tych MLOps'ach wcześniejszych, no to właśnie w tym MLOps'ie rejestrujemy modele, eksperymenty, wszystkie takie rzeczy tam do trackowania, nie? To mamy tak wykorzystane, więc tutaj trochę potrzebowaliśmy.

Mówca 2
Segment #1
Ja nie mam nic przeciwko, powiedziałbym, że nawet bardzo lubię.

Mówca 1
Segment #1
No to ten, to można byłoby teraz to zgrać właśnie z tym, z tą Llama Factory. Nie wiem teraz, możliwe, że to na pierwszy etap będzie trzeba to jakoś nawet, ten, nie wiem, dla uproszczenia, rozumiem, że może trzeba będzie to ominąć. Natomiast, no w każdym razie ten MLFlow jest tutaj, jest taki namespace i teraz kto tam może się łączyć do tych serwerów? W zasadzie tylko taki wybrany jeden serwis z Gateway'a. Czyli my na przykład mamy takie reguły autoryzacji tutaj napisane, że tam jakiś tam konkretny serwis tam tylko może wywoływać te modele. I tak naprawdę cały ruch taki z tych, z klientów takich aplikacyjnych powinien przechodzić przez ten, przez taki system, Gateway, tak? I on w zasadzie wystawia tam na zewnątrz te różne interfejsy, powinien tak jakby API Cloud Completion na przykład, no i gdzieś tam od razu jeszcze różne takie elementy załatwia typu na przykład guardrailsy, jakieś tam autoryzacje, czy jakieś takie bardziej, wiesz, tych, co tam stukają, ten logowanie requestów, responsów, no tego typu rzeczy, nie? Bo ten Gateway załatwia. Więc teoretycznie, no mamy dwie ścieżki. Tu trzeba byłoby się potem zastanowić, czy powinniśmy się łączyć bezpośrednio do tych serwisów, czy raczej przez Gateway'a, nie? To znaczy, jak gdzieś tam ten Gateway, no tutaj trzeba będzie się zastanowić, tak? Jaki ten flow.

Mówca 2
Segment #1
Da się w ogóle bezpośrednio?

Mówca 1
Segment #1
No teoretycznie się da, jak jesteś na tym samym klastrze, to wiesz, to no to można po prostu odbezpieczyć taką ścieżkę, tak?

Mówca 2
Segment #1
Weźmy poprawkę, że tam może być WebUI i nie wiem, czy to wtedy nie wymaga proxowania sobie portów.

Mówca 1
Segment #1
To znaczy, jak to WebUI? W którym miejscu mówisz?

Mówca 2
Segment #1
Llama Factory UI, WebUI.

Mówca 1
Segment #1
Aha. No, teraz kolejna rzecz, o której warto, żebyś wiedział, bo jest taka konsola do testowania promptów, która już jest też gotowa, ten, w jakimś tam, napisana w Streamlit'cie i na przykład można tu sobie wybrać jakiś model, który jest wystawiony na tym Gateway'u i go sobie tam popromptować, nie? Czyli na przykład my w tej chwili mamy tak dosyć zautomatyzowany sposób tam, wiesz, wystawienia tego serwisu z modelem na środowisku i tutaj, no to żeby to się pojawiło na Gateway'u, taki nowy model, to tam trzeba jakąś konfigurację w takim Strapi tam uzupełnić. Pewnie też dało.

Mówca 2
Segment #1
Kojarzę Strapi, to jest ten CMS do wszystkiego, tak?

Mówca 1
Segment #1
Tak, tak.

Mówca 2
Segment #1
No to korzystałem.

Mówca 1
Segment #1
Dokładnie. No oni z tego korzystają tutaj pod spodem, nie? W tym, w tym, w tym Gateway'u. Czy ta konsola to tak ci pokazuje, że coś takiego już jest, nie?

Mówca 2
Segment #1
Jasne.

Mówca 1
Segment #1
Żebyś tam sobie układał w głowie, nie musimy z tego korzystać, jeśli ta Llama Factory ma coś tam lepszego, wygodniejszego do zastosowania, no to może to być to. Natomiast.

Mówca 2
Segment #1
Będzie do porównania na pewno.

Mówca 1
Segment #1
Tak. Więc tutaj na przykład możemy skorzystać z tego rozwiązania. Oni teraz dorabiają, znaczy ja zaznaczyłem coś takiego, że my będziemy chcieli, będziemy potrzebowali takiego frontu, żeby móc pobawić się z tymi wytrenowanymi modelami, więc no, żeby tam gdzieś tam, nie wiem, mieli z tyłu głowy, że możemy do nich wrócić z czymś takim, żeby tutaj też jakiś taki, wiesz, autoryzację tutaj zapewnić odpowiednią, no bo w tej chwili to jest tak, że to jest po prostu, że masz dostęp do czegoś takiego i wtedy masz dostęp do wszystkich modeli, co nie do końca jest, wiesz, pewnie tak jakbyśmy chcieli, tylko pewnie każdy dobrze, żeby tam, wiesz, jeżeli ja wytrenuję jakiś model, no to pewnie dobrze, żebym, no że nie wszyscy do niego mieli dostęp, tylko właśnie ja, tak? Albo na przykład, nie wiem, w ramach mojego workspace'u, żeby ten dostęp był, nie? Więc to jest taka rzecz, która też tam zaznaczyłem, że też testujemy teraz takie rozwiązania, ten, właśnie z jakimś UI'em i tak dalej. Nie wiem, czy do końca będziemy potrzebowali tego od nich, natomiast, że żeby gdzieś tam już wstępnie sobie w głowie coś takiego układali, że możemy przyjść z takim requestem za jakiś czas, nie? Żeby oni to tutaj taką, powiedzmy, to, żeby tą multitenancję jakby zapewnić, to żeby sobie o czymś takim myśleli. Więc tutaj to też do ciebie taka informacja, że taki byt istnieje, tutaj został napisany. No co prawda on tylko takie coś ma, tak? No ale w zasadzie do takich modeli generatywnych, ten, no to w zasadzie się nadaje, a pewnie, nie wiem, czy Llama Factory ma do tych, nie wiem, jakichś modeli klasyfikacyjnych?

Mówca 2
Segment #1
Nie, tam bardziej jest ten pod fine-tuning UI.

Mówca 1
Segment #1
Tak, tylko że możesz tam pewnie sfine-tunować jakiś model taki, wiesz, nie wiem, szkatnerowy, który nie będzie ci zwracał, wiesz.

Mówca 2
Segment #1
Tak, dokładnie, więc nawet pewnie sądzę, że połączenie obu tych narzędzi będzie najlepszym rozwiązaniem.

Mówca 1
Segment #1
No. Więc to jest tyle, jeśli chodzi o to serwowanie, nie? To, co jeszcze alternatywnie, to ci może mignę takim obrazkiem, gdzie tam sobie tak luźno myślałem, jak i na przykład nie korzystając z tego Argo, moglibyśmy też sobie ten poradzić z wykorzystaniem obecnych narzędzi. Nie mówię, że to jest dobre rozwiązanie.

Mówca 2
Segment #1
Jeżeli nie mamy Argo Pipelines, to ja nawet go nie będę propagował, bo ja nawet za nim nie przepadam, jakby, jeżeli mam być szczery. Jakby po prostu ja zrozumiałem, że my mamy cały stack Argo u siebie jakby zsetapowany i dlatego jakby przyjąłem, że Argo.

Mówca 1
Segment #1
Przynajmniej wiesz co, przynajmniej ja nic o tym nie wiem.

Mówca 2
Segment #1
No, bo jest miliard lepszych narzędzi, lepszych do pipelinów jakichkolwiek, włącznie z Jenkins, można lubić bądź nie, niż Argo Pipelines. Nawet Tekton jest lepszy.

Mówca 1
Segment #1
No to ten, no to w każdym razie ja nie mam też nic przeciwko Argo Pipelines, tak? Ostatni raz to widziałem parę lat temu, jak jeszcze rozważaliśmy Kubeflow, tak? Żeby na przykład ten w tą stronę iść, ale to ten, to później ta moja, wiesz, zainteresowanie trochę się tym skończyło. I ja tak sobie trochę tak patrząc, jak ta Llama działa, to wyobrażałem też, że moglibyśmy mieć taki flow, gdzie przychodzi sobie data scientista, no z tym UI'em byłoby fajnie go mieć, ale to zaraz ten, zakładając, że no UI nie do końca nam się tutaj przyda, no i że generalnie taki data scientista, nie wpisałem, to jest, ale ten, przygotowuje tą konfigurację tego joba, takiego powiedzmy z Llama Factory, no to, że on tam pushuje to w jakieś odpowiednie miejsce w GitLabie, tak? W jakieś repo, które ma tam, czy tam w grupę taką GitLabową, w której może sobie tworzyć projekty. Odpala się automatycznie tam jakiś pipeline taki, na przykład w Jenkinsie, mógłby być też w GitLab CI'u, natomiast w Jenkinsie mamy więcej takich już po, wiesz, jakby więcej tych pipelinów na razie napisanych. Niby przełączamy się na GitLab CI, natomiast na razie to trochę ugrzęzło na tym, że dla tych budujących dockery te pipeliny, no ten bardzo długi czas jest budowania, że tutaj jednak ten Jenkins pomimo tego, że ma jakieś ograniczone te dyski i tak dalej, to jednak lepiej tam te rzeczy cache'uje w tej obecnym rozwiązaniu i wstrzymaliśmy się z tym migrowaniem na razie na te GitLabowe pipeliny. Więc no w Jenkinsie też mamy jakieś takie przykłady typu wywoływanie airflow'ów i tak dalej, nie? No i to, co sobie na przykład wyobrażałem, to że na przykład tutaj jakby na podstawie tej konfiguracji jest triggerowany rodzaj takiego daga, który został przygotowany wcześniej, tam powiedzmy jako ten taki szablon tego procesu, takiego pipeline'iku, który na przykład, nie wiem, zapisze nam powiedzmy jakieś parametry, zarejestruje na przykład eksperyment w MLFlow, wyjmie stamtąd, nie wiem, model na przykład, znaczy model to może później. W każdym razie, no jeżeli trzeba właśnie to coś tam na przykład wyjmie jakiś model z tego MLFlow'a, tam ten do jakiegoś tam podręcznego dysku, co jeszcze? Mamy to już teraz tak robione w tych kadrowych procesach, że na przykład te te taski, które są przetwarzane w ramach tego, tak jakby kroki w Airflow, one mogą być z wykorzystaniem tych takich operatorów Airflow'owych, ale też tam można je odpalać jako tam pody w Kubernetesie. To nie do końca są joby, może to jest takie mniej szczęśliwe, ale to jest taki, powiedzmy tam, ten, odpala się pod, który wykonuje jakiś tam krok tego pipeline'u, nie? I takim krokiem może być między innymi wywołanie tego tej Llama Factory, tak? To znaczy takiego już przygotowanego obrazu, który tam generalnie na podstawie tej konfiguracji mógłby wykonać jakieś zadanie. No i co tutaj byłoby ten, jakby plusem, że na przykład, no mamy tego Airflow'a jakoś tam już w dużej mierze wykorzystywanego i tutaj byłby podgląd do tego, co się dzieje w tym pipeline'ie, tak? Jakby była jakaś konsolka dla użytkowników. Tutaj też tak myślałem o tym, że w jaki sposób można byłoby takie tą multitenancy zapewnić, tak? Czy to też nie jest tam nowe, bo tak wcześniej trochę się do tego przymierzaliśmy w innym tam scopie. To, że każdy taki workspace jakby logiczny by miał swój tam namespace, tak? Gdzie by się tworzyły te joby, właśnie tam zgodnie z tymi punktami, które tam wypisywałeś, ten, w którymś tam z tych artykułów. I to też byłby ten MLFlow dedykowany dla takiego tenanta. I to moglibyśmy, żeby nie było tak, no bo u nas, żeby wystawić aplikację poza klaster, to trzeba dla każdej takiej aplikacji wystawić jakiś taki endpoint dedykowany i tam jakieś certyfikaty wygenerować, masę jakichś DNS-ów i tak dalej, ale to ostatnio też gadałem trochę z CDO, żeby może wyjść z tego modelu i żeby na przykład zrobić coś takiego, że jakiś taki namespace, gdzie byłby gateway zdefiniowany, żeby na to był zapięty to całe te nasze ze standardów konteneryzacji, jakieś takie powiedzmy te certy, te całe virtual hosty na F5 i i i i te wszystkie tam powiedzmy rzeczy realizowane przez inne zespoły, a że na przykład na podstawie prefiksów wtedy można byłoby się na odpowiedniej instancji gdzieś tam, wiesz, ten ruch kierować, nie? No to bardziej to trochę może taki temat związany z tym, jak u nas są te serwisy wystawiane, nie? No i tutaj, a dobra, bo tutaj w zasadzie dwa takie MLFlowy narysowałem. Jeden taki do rozważenia, gdzie na przykład ten, no bo gdzieś fajnie byłoby rejestrować te wszystkie, wiesz, eksperymenty, jakieś metryki, te te rzeczy, które byśmy chcieli, no nie wiem, w jakimś takim repozytorium i ten wyjść, ten wynikowy model, tak? Żeby gdzieś tutaj móc zapisać w takim MLFlow, natomiast też sobie wyobrażam, że fajnie byłoby mieć gdzieś tam te modele takie, powiedzmy, jakieś takie repozytorium z tymi bazowymi modelami. Ono mogłoby być gdzieś tam, no tutaj nie mówię, że to jest takie idealne rozwiązanie, ale na przykład tak jak sobie kiedyś wyobrażałem to, że na przykład u nas, tak jak w wielu procesach jest ten MLFlow wykorzystywany, więc tam mógłby być taki MLFlow, nie wiem, jakiś komonowy, w którym by była tam, nie wiem, te modele takie bazowe, które można byłoby sobie fine-tunować, tak? Czyli tam współdzielone, tak? Żeby tam trochę już trochę wyjść w tą stronę multitenancy. No i to jest takie, i teraz jeszcze tak na szybko, jakbym ten, w kontekście tych kosztów i ten, no bo tutaj by się zrobiło bardzo dużo potencjalnie tych instancji, tak? Takich Airflow'ów, MLFlow'ów. To trochę sobie tam analizowaliśmy jeszcze zanim weszliśmy w te Llama Factory, jak to trochę usprawnić takimi zarządzaniem takimi workspace'ami, bo my teraz stawiamy coś takiego, takie środowisko w ogóle MLOps'owe, właśnie między innymi z Airflow, z MLFlow, jeszcze z innymi trochę serwisami, dla każdego tenanta, tylko ci tenanci to są tacy bardziej, to nie jest jakiś projekt, który tam chwilę tam coś podłubie i ten zaraz tam się zawija, tylko to jest taki jakiś cały zespół data science, tak jak teraz mamy tych ludzi tam z tego ryzyka, z CRM'u, to oni mają takie środowiska swoje MLOps'owe, tak? Natomiast tutaj trochę pojawiły się takie głosy, że to może jest zbyt grubo i że na przykład bardziej trzeba byłoby tak myśleć, że na przykład, nie wiem, jak jest jakiś zespół, robi różne projekty, to tam jakaś separacja powinna być jednak zapewniona, więc tutaj pomysł był taki, żeby coś pomiędzy projektem a takim zespołem data science zagranić, powiedzmy coś, co moglibyśmy nazwać workspace'em, to by miało jakiś tam scope, który byłby definiowany na poziomie tego, jakby ten workflow był tworzony, no i też te workspace'y moglibyśmy, jakby one nie musiałyby ciągle stać, to znaczy, jeżeli byłyby takie elementy, że to znaczy taka potrzeba, że nie wiem, ten model został wytrenowany i on później ten, gdzieś tam, no nie ma potrzeby kontynuacji tak jakby pracy tego środowiska, to moglibyśmy je zaorać, tylko gdzieś przenieść te artefakty wynikowe, albo na przykład wygaszać takie środowiska, wtedy przynajmniej, żeby tam nie spalały jakichś kosztów, które nie są takie duże też z takich aplikacji. Co jest takie trochę, wiem, że alternatywnie do tego ten, ale to chciałem ci tak pokazać, co jeszcze można byłoby z tych naszych stacków wykorzystać alternatywnie.

Mówca 2
Segment #1
To dla mnie to jest jak najbardziej okej, jak najbardziej wartościowe.

Mówca 1
Segment #1
No tak, to cieszę się, nie mówię, że to musi tak być w tą stronę, ale no to wiem, że tak jakby no tutaj trochę dla ciebie wszystko jest tam jakby na nowe rzeczy, bo nie miałeś okazji się zapoznać z tymi MLOps'ami, ale to, żebyś widział, to jest trochę podobne do tego, jak teraz MLOps'y działają, bo MLOps'y tak działają i ludzie są przyzwyczajeni do tego flow typu, że coś commitują jakiś projekt kadrowy do GitLab'a, Jenkins się odpala, albo nawet sami mają tutaj wjazd do Jenkins'a i odpalają flow, ten, który generuje jakiś duck airflow'owy i te dugi airflow'owe mniej więcej tak się tam przetwarzają, co jest MLFlow i tak pracują ci data scientist'ci w tych swoich tam obecnych namespace'ach, nie? No i to tyle, co chciałem powiedzieć, nie? To teraz możemy, nie wiem, czy teraz, bo już jest po 16:00, to nie wiem, czy tam, jak tam planujesz, planujecie.

Mówca 2
Segment #1
Ja jeszcze jestem, aczkolwiek ja wydaje mi się, że teraz najlepiej na podstawie tego, co dostałem od ciebie, przejrzeć sobie to jeszcze, bo ja mam jeszcze dzisiaj dużo czasu, rozpisać i żebyś miał już takie idee, co i jak już na małych klockach bezpośrednio u nas na serwisach i tak dalej.

Mówca 1
Segment #1
Dobra, dobra. A poczekaj, a chcesz jakieś takie założenia przejść ze mną, bo to może to by było warto, wiesz, zczekować, bo ty tam wypisywałeś jakieś założenia i bardzo słusznie w tych różnych tych, w tych swoich artykułach, to ja ci mogę na przykład na niektóre od razu już tam feedback przekazać, nie?

Mówca 2
Segment #1
Tak naprawdę to jakbyś mógł spojrzeć dopiero na to do, ten artykuł, czy tam to deploy, przepraszam, to to jest jedyny artykuł, w którym jakieś założenie można by było czekować, bo wszystkie inne to były bardziej analizy.

Mówca 1
Segment #1
Aha, bo te warianty tam w tych wariantach.

Mówca 2
Segment #1
Tak, nie, to to były metaanalizy, to nie ten moment.

Mówca 1
Segment #1
Aha, dobra. No bo tam właśnie to te, jakbyś się tam zastanawiał nad tymi, co u nas, na czym u nas stanęło z tą izolacją i ten, no to to ci mogę tam powiedzieć, tak, jak to wygląda, ale to nie wiem, czy to jest dla ciebie teraz istotne, nie?

Mówca 2
Segment #1
Ogólnie tak, teraz nie.

Mówca 1
Segment #1
No dobra, okej, patrzę, co jeszcze. No i ogólnie tak, jeśli chodzi o ten gujać, jeszcze to ci ten, mogę ten, bo się też zastanawiałem, w sensie na ile ten UI od Llama Factory w ogóle da się sensownie u nas wykorzystać, nie? No bo ogólnie fajnie byłoby mieć taki ten, taki interfejs użytkownika, ja tam nie miałem za bardzo teraz czasu, żeby samemu sobie popatrzeć, jak to, wiesz, się tam pobawić tym UI'em, natomiast tak, to pierwsze na przykład tak się zastanawiam, skąd on, skąd tam, bo tam podejrzewam, że są takie pola wyboru, tak, jakiegoś modelu, ten, nie wiem, jakiegoś datasetu, skąd on wie, co tam może zaproponować użytkownikowi? Coś skanuje, jakiś tam katalog?

Mówca 2
Segment #1
Tak, bo można zrobić albo grupę configu, albo config bezpośredni dla userów, ale głównie to jest tak, że grupa i po prostu cały hugging face i sobie to skanujesz, dlatego tam jest hugging face podpięty.

Mówca 1
Segment #1
A ta aplikacja, jak ona by się na przykład zachowała, jakby na przykład dwie równoległe, wiesz, sesje by tutaj się wbiły?

Mówca 2
Segment #1
Nie mam pojęcia, nie sprawdzałem, sorry.

Mówca 1
Segment #1
Wiesz, tak?

Mówca 2
Segment #1
Nie wiem.

Mówca 1
Segment #1
Bo właśnie się zastanawiam, czy ona się na, ten, ta, ten, gdzie on jest, ten web UI, tak, czy on się nadaje taki do wystawienia takiego, żeby...

Mówca 2
Segment #1
Na pewno, jeżeli to web UI, bo ono tam przekazuje jakiś parametr do joba, bo pamiętam, że zrobiłem to na tej zasadzie, że nie dwie na raz, ale jakby ustawiłem sobie jedną apkę i drugą, ale to szło jakby równolegle, to one dostały inne ID'ki po prostu. No.

Mówca 1
Segment #1
Bo tam, bo tam widziałem, że on pokazuje jakby postęp tego joba, bo to wtedy, bo tak zakładałem, że, że nie wiem, tam w tym takim wariancie, co u ciebie był z Argo, albo u mnie z tym Airflow'em, no to te, te powiedzmy, te workflowy by tam miały jakiś UI, który tam ludzie by mogli podglądać, co się dzieje, no ale tutaj też ten Llama Factory też tam spoko tam na bieżąco pokazuje jakiś postęp i ten, tylko nie wiem, na ile to, bo to pewnie trzeba byłoby przerobić sam Llama Factory, tak, żeby tam powiedzmy, nie wiem, w tym momencie, kiedy on triggeruje zadanie, to na przykład striggerować job'a już w Kubernetesie pewnie, tak? No i pytanie, skąd on ma wiedzieć.

Mówca 2
Segment #1
Tak, dokładnie.

Mówca 1
Segment #1
Jak ma się odpytywać o status, tak, tego job'a? I nie wiem, czy tutaj nad tym się trochę zastanawiałeś, czy na razie jeszcze...

Mówca 2
Segment #1
Analizowałem i po prostu najlepiej odnieść się do tego kodziku w Python'ie, który tam jest dostarczany.

Mówca 1
Segment #1
Znaczy którego?

Mówca 2
Segment #1
Llama Factory po prostu.

Mówca 1
Segment #1
To się zastanawiam właśnie, czy ten UI to my w końcu od nich użyjemy, czy, czy nie, tak? No bo to pytanie, ten, jak to wystawimy, to, to teraz ile tego trzeba było wystawiać, tak? Bo to nie jest multitenant, więc tu, ten, trzeba byłoby jakoś, wiesz, ogarnąć, żeby każdy mógł sobie tam niezależnie jakby odpalić swojego job'a, sprawdzić status, idealnie to też by było, gdyby tam, wiesz, jakaś ta, nie wiem, jakby tam sprawdził za godzinę, to też by widział, wiesz, mógł to sprawdzić, tak? No i jeżeli to w ogóle to narzędzie nie za bardzo się nadaje do takich celów, to może warto, wiesz, no jakoś inaczej działać, albo na przykład właśnie poprzez te, niech będą te YAML'e, tak? Z drugiej strony. Więc tutaj to by mnie ostatecznie interesowało, jaki jest ten, jaki jest ta wartość dodana z tego UI'a, który jest tutaj, który daje...

Mówca 2
Segment #1
To jeszcze sobie na to zerknę.

Mówca 1
Segment #1
No właśnie, bo też tam parę rzeczy już też, że w kontekście tego, jakby tego w kontekście z tego LLP'a można byłoby jakby zrobić takie właśnie, że takie u nas naturalne było użycie takiego LLP'a, żeby model trenowany w tym modelu miał trochę na wzór jakby jakaś nowa wersja modelu. No i też przejście tutaj serwowania to też nie byłoby jakieś takie złożone, bo my możemy się jakby w serwisie tym takim wielelanowym moglibyśmy się zapiąć na innego LLP'a, tak? Czyli tutaj, wiesz, instancji serwisowej się tam, tak, takiej instancji albo innej, jeżeli tam byśmy to multitenance jakoś chcieli zrobić w taki sposób, żeby było dużo instancji na show. To też do zastanowienia, tutaj też nie mówię, że to, to rzucam takie pomysły bardziej niż, że tak musi być, nie? To to to najbardziej, oczywiście swobodnie challenge'ując to i na przykład, że tutaj się jakiś bałagan zrobi albo coś tam, wiesz, no to bardziej chciałem tutaj pokazać.

Mówca 2
Segment #1
Jasne.

Mówca 1
Segment #1
Jakie są narzędzia. No dobra, czyli ten, to, czyli co, weźmy jakoś tam w poniedziałek sobie zerknęli na to, tak?

Mówca 2
Segment #1
Tak, będzie najlepiej. Halo.

Mówca 1
Segment #1
No dobra. A, dobra, to jeszcze jedna rzecz taka, co mi przyszła do głowy, co tam, ten, uprawnienia jakby z takim. Bo my w tej chwili mamy tak, że z tym, co napisałem w tym LLP'ie, jest związany jakiś kod z zapisanych usług, to tak jakby instancją nie jest to, że jest to jakiś kod, tylko że na przykład często też można, można jakąś separację dostępów dawać, czyli możesz tego pilnować, wiesz, do jakiejś warstwy aplikacyjnej po prostu nie da się, wiesz, pobrać rzeczy, do których nie masz dostępu, tak? No bo powiedzmy, jeżeli tam jakiś EPROM, CRM'owy czy gdzieś tam nie ma wjazdu, to nie ma, tak? Tak, natomiast jest to ograniczone oczywiście, jeżeli byś chciał zrobić taki multitenance w ramach tej aplikacji, no bo konto serwisowe to GCP jest jednym z tych związanych. I tutaj stosujemy taki mechanizm jakby workload identity, który powoduje to, że tam momentalnie to konto Kubernetes'owe, ten, na którym działa serwis, jest utożsamiane z kontem tam IoT GCP, co po prostu nie musisz nic z wolna żadnego możesz ściągać, po prostu jak serwis używasz z nowego API, możesz dać tutaj tego pakietu, no to jest rozpoznawany jako tam, powiedzmy, to konto serwisowe, które jest tam, powiedzmy, w API, tak? I stworzymy ten konto GCP serwisowe, tak?

Mówca 2
Segment #1
Jasne, okej.

Mówca 1
Segment #1
Dobra. No dobra, no to tam spokojnego ten wieczoru. No wiesz, wiadomo, że się zdarzają takie sytuacje, więc jak tam, znaczy jak ten...

Mówca 2
Segment #1
Jakby Pawle, nie mierz wszystkich swoją.
