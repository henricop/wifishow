<div align="center">

<img src="Resources/icon-preview.png" width="128" alt="WifiShow">

# WifiShow

**Analisador de Wi-Fi nativo para macOS.** Monitora as bandas 2.4 / 5 / 6 GHz em tempo real.

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Universal](https://img.shields.io/badge/binary-universal-0A84FF)](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

SwiftUI · Swift Charts · CoreWLAN · sem dependências externas · 2.5 MB

</div>

---

## O que é

Um analisador de espectro Wi-Fi que roda no seu Mac. Mostra quais redes ocupam
quais canais, com que largura e com que força — para você escolher o canal certo
do roteador e encontrar o melhor lugar para posicioná-lo.

Sem assinatura, sem versão Pro, sem telemetria, sem conta. **O app não acessa a
rede em nenhum momento** — só lê o rádio Wi-Fi local.

## Funcionalidades

| Tela | O que faz |
|---|---|
| **Visão geral** | Rede conectada: RSSI, ruído, SNR, canal, largura, frequência central, segurança. Contagem por banda e sinal dos últimos 2 minutos. |
| **2.4 / 5 / 6 GHz** | Analyzer espectral da banda — cada rede desenhada na frequência e largura que realmente ocupa — mais a tabela completa. |
| **Histórico de sinal** | RSSI e SNR da rede conectada, 1 amostra por segundo, até ~12 minutos. Para caminhar pela casa e mapear a cobertura. |
| **Congestão de canais** | Quantas redes por canal e, em 2.4 GHz, qual dos canais 1 / 6 / 11 está mais limpo. |
| **Teste de velocidade** | Download, upload, latência e **responsividade (RPM)** sob carga, via `networkquality`. |
| **Detalhes do Wi-Fi** | 22 métricas da conexão atual, cada uma com explicação do que significa. |
| **Todas as redes** | Tabela única com todas as bandas, ordenável por qualquer coluna. |

Varredura configurável (3 / 5 / 10 / 30 s) na barra de ferramentas. `⌘R` varre na hora.

## Requisitos

**Para usar o app:**

| | |
|---|---|
| Sistema | macOS 14.0 (Sonoma) ou superior |
| Hardware | Apple Silicon ou Intel — o binário é universal |
| Permissão | **Localização** (obrigatória, explicada abaixo) |
| Wi-Fi 6E | Opcional. A aba 6 GHz só mostra redes se o Mac e o roteador suportarem |

**Para compilar:**

| | |
|---|---|
| Xcode Command Line Tools | `xcode-select --install` |
| Swift | 5.9 ou superior (`swift --version`) |
| Xcode completo | **Não é necessário** |
| Dependências | Nenhuma. Só frameworks do sistema |

> Testado em macOS 26.6.1 com Swift 6.2.1 e Command Line Tools 26.1.
> O mínimo declarado é macOS 14.0 porque o app usa `@Observable` e
> `ContentUnavailableView`, introduzidos nessa versão.

## Instalação

```bash
git clone https://github.com/henricop/wifishow.git
cd wifishow
./build.sh
open WifiShow.app
```

Para deixar no Launchpad:

```bash
cp -R WifiShow.app /Applications/
```

### Na primeira execução

O app é assinado **ad-hoc** (sem certificado de desenvolvedor pago), então o
Gatekeeper reclama na primeira abertura. Como você mesmo compilou o binário a
partir deste código, é seguro liberar:

```bash
xattr -dr com.apple.quarantine WifiShow.app
```

Ou: clique com o botão direito no app → **Abrir** → **Abrir**.

### Por que ele pede Localização

Desde o **macOS 14**, o sistema trata a lista de redes Wi-Fi próximas como dado
de localização — porque dá para inferir onde você está a partir dos BSSIDs. Sem
a permissão, o CoreWLAN devolve `ssid` e `bssid` como `nil`, e qualquer
analisador vira uma lista vazia.

Só a permissão é usada: o app **não** lê sua posição GPS, não guarda histórico
de lugares e não tem acesso à rede (nenhuma conexão sai da máquina).

## Comandos

```bash
./build.sh            # compila universal (arm64 + x86_64) e assina ad-hoc
./test.sh             # suíte: plano de canais + parsing do networkquality
./Tools/make-icon.sh  # regenera o ícone a partir do código
```

## Como funciona

### Dois loops independentes

`Sources/Scanner.swift` roda duas tarefas separadas, por um motivo concreto:

- **Varredura** (3–30 s) — `CWInterface.scanForNetworks`. É **bloqueante**
  (2–4 s) e o macOS aplica throttle. Roda em `Task.detached` e nunca abaixo de 3 s.
- **Telemetria** (1 s) — lê apenas a interface conectada (`rssiValue`,
  `noiseMeasurement`). Custo desprezível, e é o que dá ao histórico
  resolução de 1 segundo sem torrar o rádio com varreduras.

### Canal primário ≠ centro da portadora

Esta é a parte que mais separa um analisador correto de um aproximado.

O CoreWLAN entrega o **canal primário**. Uma rede de 160 MHz não transmite
centrada nele — ela ocupa um bloco inteiro, centrado em outro ponto:

```
Rede no canal 44, largura 160 MHz

  ingênuo →  centro 5220 MHz                    ✗  30 MHz fora do lugar
  correto →  centro 5250 MHz (canal 50)         ✓  ocupa 5170–5330 MHz
```

Como cada banda resolve isso:

- **5 GHz** — os blocos são irregulares: a faixa UNII-3 (149–165) quebra o
  padrão de 4 em 4 dos canais anteriores. Resolvido com tabelas canônicas de
  40 / 80 / 160 MHz.
- **6 GHz** — regular, resolvido por fórmula: `base = span·⌊(ch−1)/span⌋ + 1`.
- **2.4 GHz** — a direção do canal secundário (HT40+ ou HT40−) só existe no
  Information Element do beacon, que o CoreWLAN **não expõe**. O app centra no
  primário — aproximação conhecida e assumida, não um descuido.

`./test.sh` valida 9 casos, incluindo os limites de UNII-3 e 6 GHz.

### Teste de velocidade sem servidor

`Sources/SpeedTest.swift` chama o **`/usr/bin/networkquality`**, a ferramenta
nativa do macOS. Não há infraestrutura própria: o binário da Apple negocia com
o edge mais próximo.

Além de banda, ele mede **responsividade em RPM** (Roundtrips Per Minute) —
quantas idas e voltas a rede sustenta *enquanto está saturada*. É a métrica que
explica por que uma conexão de 500 Mbps ainda trava numa chamada de vídeo.
Abaixo de 200 RPM indica bufferbloat.

O parsing fica isolado em `SpeedResult.parse(_:)`, separado da execução do
processo, e é testado offline contra uma saída real gravada em
`Tests/fixtures-networkquality.json`.

### Detalhes com explicação

`Sources/Details.swift` reúne o que o CoreWLAN expõe **só da interface
conectada** — taxa de transmissão, potência, código do país, MAC do adaptador,
modo PHY — mais os endereços IP obtidos via `getifaddrs`.

Cada uma das 22 métricas traz uma explicação acessível em popover. A ideia é
que alguém sem formação em redes consiga ler a tela inteira sem pesquisar fora.

> Nota sobre `transmitPower`: a Apple documenta o valor como mW, mas em Macs
> modernos o número reportado não corresponde a miliwatts reais (o limite legal
> gira em torno de 100 mW). O app mostra o valor bruto e diz isso na explicação,
> em vez de carimbar uma unidade errada.

### Ruído e SNR

O CoreWLAN só preenche `noise` da interface **conectada**; para as vizinhas
devolve `0`. O app usa o ruído medido localmente como piso para estimar o SNR
das outras redes.

Ou seja: **o SNR da rede conectada é medido; o das vizinhas é estimado.**
O código deixa isso explícito em vez de fingir precisão que não existe.

### Curva espectral

Cada rede é uma parábola com pico no RSSI e base na largura ocupada:

```
y = piso + (rssi − piso) · (1 − d²)      d = (x − centro) / (largura/2)
```

## Estrutura

```
Sources/
  Model.swift       domínio: banda, plano de canais, rede, curva espectral
  Scanner.swift     CoreWLAN + CoreLocation, os dois loops
  Details.swift     retrato da interface conectada + métricas explicadas
  SpeedTest.swift   networkquality: execução e parsing
  Views.swift       gráficos (Swift Charts), tabela, telas de banda
  ViewsDetail.swift telas de velocidade e detalhes
  App.swift         navegação, toolbar, gate de permissão
Tests/
  ChannelPlanTests.swift
  SpeedTestParsing.swift
  fixtures-networkquality.json
Tools/
  MakeIcon.swift   ícone gerado por código (CoreGraphics), sem editor gráfico
Resources/
  WifiShow.icns
build.sh  test.sh
```

## Limitações conhecidas

- **Assinatura ad-hoc.** Sem conta Apple Developer paga, não há notarização.
  Para distribuir fora do GitHub seria preciso assinar e notarizar.
- **Sem modo monitor nem captura de pacotes.** Nenhum app fora do kernel
  consegue isso no macOS moderno. O que dá para ver é o que o CoreWLAN expõe.
- **PHY mode das vizinhas não é exposto** no resultado do scan — só da rede
  conectada (visível na tela de Detalhes). A coluna existe no modelo das
  vizinhas, mas fica `-`.
- **O teste de velocidade leva ~35 s** e satura a conexão de propósito: é
  assim que a responsividade sob carga é medida.
- **2.4 GHz com 40 MHz** é centrado no canal primário (ver acima).
- **Wi-Fi 7 (802.11be)** ainda não aparece no enum `CWPHYMode` do SDK atual.

## Contribuindo

Issues e PRs são bem-vindos. Antes de abrir um PR:

```bash
./build.sh && ./test.sh
```

Ideias já mapeadas, se quiser pegar uma:

- [ ] Ícone na barra de menu com o sinal sempre visível
- [ ] Gráfico de cobertura por cômodo a partir do histórico
- [ ] Exportar varredura em CSV / JSON
- [ ] Scanner de dispositivos na rede local
- [ ] Localização do texto (hoje só português)

## Licença

[MIT](LICENSE) © 2026 Henrico Piubello
