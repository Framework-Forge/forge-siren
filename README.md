# Forge Siren

Controlador de sirene da Forge, baseado no Renewed Sirensync / PMA Sirensync.
Integração nativa com **PR Bridge**, sem importação, chamadas ou dependência direta de ox_lib.

A interface é Svelte 5: gabinete preto, botões retroiluminados e visor âmbar de matriz de pontos.
Não usa fontes, imagens ou serviços externos. A versão compilada já está em `web/dist`.

## Instalação

Inicie `pr_bridge` e `pma-voice` antes de `forge-siren`:

```cfg
ensure pr_bridge
ensure pma-voice
ensure forge-siren
```

Mantenha apenas um controlador de sirene em execução: desative o Renewed/PMA original
ou outro script que controle as mesmas teclas, luzes e sons. O painel fica disponível
para o piloto (banco -1) e copiloto (banco 0) das viaturas habilitadas. Passageiros
traseiros não têm acesso. Em motos, somente o piloto pode usar o painel.
Por padrão, são habilitados a classe 18 (emergência), `polmav` e `policeb`.

O megafone usa o PMA Voice modificado nesta base. O PR Bridge e qbx_core não
foram alterados. `server.cfg` inicia agora o PMA antes do Forge Siren, e o manifest
também declara essa dependência. Reinicie a base após atualizar para carregar
as configurações de voz e o novo item do inventário. Não inicie `r_megaphone`
junto: ele foi somente referência, não é uma dependência.

## Controles

| Controle | Função |
| --- | --- |
| Q / FLASH | Liga/desliga luzes. Desligar as luzes também silencia a sirene. |
| Alt esquerdo / SIREN | Liga/desliga o som. Ao ligar, também acende as luzes. |
| R | Com som ligado, alterna o tom. Com som desligado, toca manualmente enquanto segurar. |
| E / HORN | Corneta enquanto segurar; ao soltar, restaura o tom anterior. |
| Ctrl esquerdo ou /sirene | Ativa/desativa o cursor do painel, mantendo os comandos de direção disponíveis. |
| Tecla do megafone / MEGAFONE (segurar) | Fala pelo megafone do veículo, ou pelo item equipado a pé. |
| /sirene ajustar | Abre diretamente o ajuste visual de posição e tamanho. |
| Esc | Fecha as memórias; pressione novamente para fechar o cursor. |
| OFF | Desliga luzes, sirene e corneta. |
| A1 / A2 | Seleciona diretamente o primeiro/segundo tom da viatura. |
| Setas do painel | Alternam todos os tons disponíveis, incluindo Priority quando existir. |
| F1 (botão) | Manter/desligar as luzes ao sair da viatura. |
| F2 (botão) | Manter/desligar o som ao sair da viatura. |
| B1 (botão) | Alternar o tom principal preferido. |
| B2 (botão) | Abrir preferências, três memórias pessoais e a aba ADMIN para administradores. |

F1/F2/B1/B2 são os nomes dos botões virtuais, não novos atalhos globais do teclado.
Os controles de teclado são registrados pelo PR Bridge e podem ser remapeados nas configurações do FiveM.
`controls.panel` define o padrão **LCONTROL** (Ctrl esquerdo); o cursor só abre
nos bancos autorizados de um veículo habilitado. Atalhos já salvos como F6 ou
outra tecla são preservados: para usar o novo padrão, remapeie **Forge Siren:
cursor do painel** em Configurações → Teclado → FiveM.
O padrão de `controls.megaphone` nesta cópia está como **F2** e foi preservado.
Um atalho já remapeado/salvo como F7 continua válido; confira a tecla indicada
no botão MEGAFONE e os atalhos do FiveM. As referências a F7 abaixo significam
a tecla atualmente vinculada ao megafone.
Combinações especiais/controles não alfanuméricos remapeados podem ser usados fora do cursor;
no painel interativo, os botões de mouse continuam disponíveis.

Com o cursor aberto, inclusive no editor de posição/tamanho, o teclado continua
controlando aceleração, ré/freio, direção e freio de mão. Movimento e cliques do
mouse ficam reservados ao painel: não giram a câmera, não ativam direção pelo
mouse nem disparam armas do veículo. Espaço não aciona o último botão clicado;
use clique ou Enter para ativar um botão pelo painel.
A tecla do cursor tem um único responsável no cliente Lua, evitando alternância duplicada.
Enquanto o cursor, configurações ou editor estiverem abertos, Esc fica reservado
à NUI: cancela a edição, fecha as memórias ou sai do painel sem abrir a pausa do
GTA. O bloqueio consome também a soltura dessa tecla ao fechar o cursor; depois
disso, o menu de pausa volta a funcionar normalmente. A condução permanece livre.

## Megafone veicular e portátil

- **Veículo:** piloto/copiloto de veículos autorizados seguram F7, ou o botão
  MEGAFONE com o cursor aberto. Em motos, somente piloto. Não exige item.
- **A pé:** use o item `megaphone` no inventário para equipar o prop, depois
  segure F7 para falar. Use novamente o item ou `/megafone` para guardar.
  O item é reutilizável: não é consumido. Foi definido em `ox_inventory/data/items.lua`;
  não foram criadas lojas, concedidos itens a jogadores nem alterados saldos.
- **Alcance:** 35 metros por padrão; efeito próprio de alto-falante. Soltar
  restaura a proximidade normal/customizada, sem criar outro modo de voz.
- Configure item, prop/animação, modelos e `controls.megaphone` em `config.lua`.
  Alcance, volumes e efeito são administrados pela aba ADMIN; os valores em
  `config.lua` são padrões usados quando não há configuração global salva.
  O PMA mantém um teto independente de 50m via `voice_megaphoneMaxRange`.
- `voice_useNativeAudio true` e `voice_enableSubmix 1` já estão configurados
  em `voice.cfg`, como exige o áudio com efeito. Não sobrescreva os natives
  de voz em outro recurso; amplificação/routing ficam dentro do PMA.
- Veículos customizados: o servidor aceita a categoria `emergency` do catálogo
  do PR Bridge ou os modelos em `megaphone.models`/`access.models`. Para modelos
  fora do catálogo, acrescente a allowlist; a classe enviada pelo cliente não
  é usada como autorização. Inclua também em `access.models` se não for classe 18.
- Transmitir pelo rádio ou entrar em chamada interrompe o megafone. Recepção
  de rádio/chamada e mute individual mantêm prioridade sobre o efeito local.
- Sessões são validadas no servidor; sair/mudar de veículo, morrer, perder o
  item, trocar personagem/bucket, desconectar ou parar os recursos encerra
  a amplificação. Heartbeat de 1s e expiração de 3s cobrem uma soltura perdida.
- Não foi adicionado loop por frame em repouso. PTT trabalha por frame somente
  durante transmissão. Os ouvintes são atualizados pelo ciclo de proximidade
  já existente no PMA, com mudanças de volume/submix deduplicadas.

### Retorno da própria voz

O retorno local já fica habilitado para o megafone veicular e portátil, com
filtro de alto-falante e volume inicial de 30%. Ele só captura enquanto há transmissão
autorizada: soltar a tecla, perder acesso ou encerrar o megafone libera o
microfone da interface. Não altera alcance/volume dos outros jogadores, nem
grava ou envia uma segunda cópia da voz.

Na primeira utilização, abra **F8**, autorize o pedido de microfone do recurso
`pma-voice` e segure novamente a tecla do megafone. O retorno usa os dispositivos
padrão do Windows/interface, não copia automaticamente o dispositivo escolhido
no menu do GTA. Use fones para evitar realimentação. Se essa captura/reprodução
não estiver disponível, o aviso será específico ao retorno; a transmissão
normal continua independente.

O efeito local usa filtros de 450–3500 Hz, reforço de médios, compressão e
saturação suave. Os outros jogadores recebem o efeito RadioFX nativo do FiveM
com a mesma faixa de frequências. São dois caminhos de áudio distintos; o
retorno local aproxima esse timbre, não é uma cópia do áudio transmitido.

Os limites são definidos na aba ADMIN. `/megafonediag` mostra `monitorStatus`,
`monitorActive`, `monitorVolume` e `effectEnabled` no F8. Ouvir o retorno testa
o caminho local, não confirma que outro jogador recebeu áudio. Depois de
atualizar, reinicie `pma-voice` antes de `forge-siren`.

### Administração global do megafone

Na viatura: **Ctrl esquerdo → B2/MEMÓRIAS → ADMIN**. A aba aparece somente
quando o servidor confirma a permissão pelo PR Bridge. São aceitos
`forge-siren.admin`, `forge-core.admin` ou os administradores da whitelist do
PR Bridge. A permissão é conferida novamente em cada salvamento; alterar a NUI
não concede acesso. Para liberar um grupo administrativo já existente, por
exemplo (não conceda a grupos de jogadores comuns):

```cfg
add_ace group.admin forge-siren.admin allow
```

Campos disponíveis:

- Habilitar o megafone, o retorno local e o efeito rádio/megafone separadamente.
- Volume máximo de retorno (0–100%, padrão 30%).
- Volume máximo para jogadores próximos (0–100%, padrão 100%).
- Volume no limite do alcance (0–100%, padrão 25%, nunca maior que o próximo).
- Alcance máximo (metros, padrão 35m), limitado pelo teto do PMA.

O volume dos ouvintes permanece no valor próximo até 5m (ou 20% do alcance,
se menor) e diminui linearmente até o valor distante; fora do alcance fica
mudo. Os percentuais são ganhos relativos ao áudio: não são decibéis nem
impõem um volume físico aos fones/alto-falantes do jogador.

**Salvar global** grava no KVP do servidor
`forge_siren:megaphone:global:v1`. Vale para megafone veicular e portátil, todos
os jogadores e transmissões em andamento. Os valores persistem ao reiniciar
o recurso/cidade, sem consulta ao banco ou novos state bags. Configuração
salva prevalece sobre os padrões de `config.lua` e as convars de megafone
de `voice.cfg`; `voice_megaphoneMaxRange` permanece independente. As convars
replicadas hidratam jogadores que entram depois e reinícios do PMA.

Se outro administrador salvar enquanto você edita, o formulário pede
**Recarregar** e não sobrescreve seus ajustes silenciosamente. Alterações
globais não modificam memórias pessoais, posição ou tamanho do painel.

### Validação do megafone

O PMA recupera a inicialização mesmo se a voz já estiver conectada ao iniciar ou
reiniciar o recurso. As tentativas são agrupadas e cada espera de inicialização
tem limite total de 10 segundos; conexão/canal chegando depois permitem uma nova
tentativa, inclusive ao pressionar F7. Não há liberação forçada durante rádio,
chamada, desconexão ou uso de canal personalizado por outro recurso.

Se F7 não iniciar a transmissão, a notificação distingue configuração, conexão,
inicialização, personagem, proximidade, rádio, chamada e incapacidade do personagem.
Use `/megafonediag`, mesmo sozinho no servidor, e confira a linha
`[Forge Siren] Megafone:` no F8. Ela mostra o motivo e o estado local da voz, sem
identificadores de personagem nem números de canais. O diagnóstico também pode
solicitar a recuperação da inicialização; se informar que está inicializando,
aguarde alguns segundos e repita. Ele não transmite áudio nem concede o item.

Após atualizar estes arquivos, reinicie `pma-voice` e depois `forge-siren`, ou
reinicie a base. Se usar o megafone portátil, equipe o item novamente. As opções
de `voice.cfg` listadas acima já estão configuradas nesta base; não é necessário
duplicá-las em `server.cfg`. Confira `/megafonediag` e a indicação TX com F7 nos
dois contextos. Isso verifica a disponibilidade, não prova que outro jogador ouve.

Testes Lua com mocks cobrem autorização, bancos/motos, remoção do item,
expiração, rádio/chamada, mute, raio de áudio, PTT, restauração da voz,
inicialização já conectado, chegada tardia do cache, timeout, reconexão e avisos.
Testes de navegador cobrem o botão momentâneo, TX real, foco e transparência.
Ainda valide com **dois jogadores no FiveM**: dentro/fora dos 35m, ambos os
bancos da frente, garupa/traseiros, megafone portátil, rádio e telefonema.
Esses testes locais não comprovam audibilidade ou posicionamento da animação
no motor do jogo.

## Preferências e memórias

- Padrão: manter luzes ao sair, desligar som ao sair, primeiro tom como principal.
- Luzes e som têm preferências independentes. Elas conservam somente o que já estava
  ligado: entrar/sair da viatura nunca liga automaticamente um sistema desligado.
- A corneta e a sirene manual nunca persistem ao sair.
- Enquanto outro ocupante autorizado permanece na frente, sair não desliga suas
  luzes/sirene. Ao sair o último, valem as preferências de quem saiu por último.
  Em motos, a presença da garupa não mantém o acesso nem impede essa regra.
- Preferências e memórias são pessoais; luzes, som e tom audível são compartilhados
  entre piloto e copiloto. Soltar sua corneta não corta a corneta segurada pelo outro.
- O tom principal é usado na próxima ativação/entrada; escolher um tom ou carregar
  um preset não dispara a sirene por conta própria.
- B2 permite nomear, salvar e carregar três presets com persistência, tom principal
  e tamanho da interface.
- Preferências são guardadas no KVP local do recurso, neste computador/cliente.
  Não são armazenadas no banco nem sincronizadas entre computadores ou personagens.
- Ao carregar um preset cujo tom não exista naquela viatura, o controle usa o
  primeiro tom disponível; não injeta sons incompatíveis.
- O tamanho se adapta ao espaço disponível, incluindo telas 1280×720.

## Reposicionar e redimensionar

No banco do piloto/copiloto de uma viatura habilitada (em moto, somente piloto):

1. Use `/sirene ajustar`, ou Ctrl esquerdo → B2 → **Reposicionar / redimensionar painel**.
2. Arraste o painel para movê-lo. Arraste o canto superior esquerdo para mudar seu
   tamanho, ou use a barra de tamanho (40% a 130%).
3. As setas ajustam a posição em 1 pixel; Shift + seta ajusta em 10 pixels.
4. **Salvar posição** guarda posição e tamanho no KVP local. **Cancelar** ou Esc
   descarta o ajuste. **Restaurar** prepara a posição/tamanho padrão; salve para aplicar.

Durante a edição, os botões e atalhos de sirene não são acionados pelo painel.
O estado real da viatura permanece visível. Perder acesso ao banco fecha o editor
sem salvar. A posição fica separada dos presets e é proporcional à resolução;
o painel é limitado às bordas da tela para continuar acessível.

### Transparência da NUI

O esquema escuro fica somente nos elementos do painel, nunca no documento raiz.
O fundo de `html`, `body` e `#app` é transparente, inclusive antes de carregar o
JavaScript. O teste de regressão compõe a NUI sobre um fundo colorido e verifica
o pixel renderizado com painel oculto, configurações abertas e editor ativo.
Conferir só `background: transparent` no `body` não detectava o canvas opaco.

## Configuração e sons adicionais

Edite `config.lua` para alterar teclas iniciais, posição da interface, preferências
iniciais e grupos de áudio. Grupos específicos devem vir depois do grupo base.
`access.classes` habilita classes de veículos e `access.models` inclui modelos
especiais, como helicópteros de emergência personalizados. A regra dos bancos
continua igual para esses modelos; `bike` é sempre exclusivo do piloto.

```lua
{
    models = {
        [joaat('police5')] = true,
    },
    sirenModes = {
        { audioName = 'MEU_WAIL', audioRef = 'MEU_SOUNDSET', label = 'WAIL' },
        { audioName = 'MEU_YELP', audioRef = 'MEU_SOUNDSET', label = 'YELP' },
        { audioName = 'MEU_PRIORITY', audioRef = 'MEU_SOUNDSET', label = 'PRIORITY' },
    },
    horn = { audioName = 'MINHA_CORNETA', audioRef = 'MEU_SOUNDSET' },
}
```

O grupo específico substitui a lista inteira de tons. Assim, motos/viaturas com dois
tons não herdam um terceiro som da base. Use listas contínuas (1, 2, 3...).
`audioRef` é opcional para os sons padrão. O pacote de áudio personalizado deve
estar instalado e iniciado; este recurso não inclui sirenes adicionais.

A opção legada `sirenShutOff` é considerada apenas se não houver um padrão explícito
em `preferences.keepSound`. Preferências já salvas pelo jogador prevalecem sobre
novos valores iniciais.

## Sincronização e integração

Permanecem as chaves replicadas `stateEnsured`, `lightsOn`, `sirenMode` e `horn`.
A inicialização e cada comando são validados pelo servidor, que confirma o banco
ocupado e a sessão de acesso. Ambos os ocupantes enviam comandos ao servidor;
o copiloto não precisa assumir a propriedade de rede da viatura para controlá-la.
Comandos atrasados de uma sessão antiga não controlam uma sessão nova.
O evento legado `Renewed-Sirensync:server:SyncState` continua aceito para inicialização.

O PR Bridge fornece carregamento de configuração, cache/eventos de cache e teclas.
A NUI usa callbacks locais; não foi necessário acrescentar
APIs ao bridge. Os presets não são enviados como state bags.

O cliente recupera o áudio de viaturas que entram no alcance de streaming, evita
reiniciar sons inalterados e libera os IDs ao encerrar. Um ID em cache só é
reutilizado enquanto `HasSoundFinished` indicar reprodução ativa; se o som terminar
mas o estado continuar ligado, a manutenção já existente recria a reprodução.
Isso também vale após sair do veículo ou mudar seu proprietário de rede.
Não há consultas ao banco.
Não execute outro controlador de sirene simultaneamente. Recursos que vazam IDs
de som também podem esgotar o limite de áudio do GTA.

## Custo dos ciclos

- Mudanças de luzes, tom e corneta são tratadas por eventos e agrupadas no mesmo
  frame. Não há reconstrução da interface cinco vezes por segundo.
- Perfis de áudio, controles e dados estáticos do painel são reutilizados.
  Rótulos de teclas são conferidos a cada 5 segundos, só com o painel disponível.
- A descoberta de veículos no streaming acontece a cada 3 segundos, com lotes
  de 32 veículos por frame. Eventos de veículos ainda fora do alcance não criam
  esperas individuais a cada frame; a descoberta posterior recupera o estado.
- A manutenção a cada segundo percorre apenas veículos já registrados no cliente,
  usando o estado em cache. Continua necessária para detectar remoção, mudança
  de proprietário, luz nativa divergente e dano/recuperação da viatura.
- O bloqueio de sirene/rádio nativos continua a cada frame somente enquanto um banco
  autorizado está ativo e sem pausa, inclusive com cursor. Nesse caso são bloqueados
  também câmera/ataques/direção por mouse, mas não os controles de condução pelo
  teclado. Esse bloqueio precisa ser renovado por frame; as listas de controles
  não são recriadas a cada execução. Não foi acrescentado outro ciclo.
- Eventos de cache detectam entrada/troca de banco. Uma verificação de reserva a
  cada segundo cobre eventos perdidos; pausa é conferida a cada 250 ms quando ativo.
- Os intervalos de descoberta, lotes, manutenção e verificação de banco são
  ajustáveis em `performance`. Não há varredura periódica de jogadores no servidor.

Isso reduz trabalho redundante; não representa uma medição de milissegundos/FPS.
Para medir o ganho real, compare o recurso no resmon/profiler do FiveM no mesmo cenário.

## Desenvolvimento e testes

Dentro de `web`:

```text
npm ci
npm run build
npm test
npx playwright install chromium
npm run test:browser
```

Para testar os arquivos compilados que o FiveM usa, depois do build, no PowerShell:

```powershell
$env:FORGE_TEST_PRODUCTION = '1'
npm run test:browser
Remove-Item Env:FORGE_TEST_PRODUCTION
```

Para uma prévia interativa sem FiveM, execute `npm run dev` e acesse
`http://127.0.0.1:5173/?preview=1`. Sem esse parâmetro, a página permanece
transparente/oculta até receber o estado real do recurso.

Testes Lua (a partir da pasta do recurso, com um interpretador Lua instalado):

```text
lua tests/shared_test.lua
lua tests/admin_server_test.lua
lua tests/server_test.lua
lua tests/client_test.lua
lua tests/megaphone_server_test.lua
lua tests/megaphone_client_test.lua
```

Na pasta `pma-voice`, execute também `lua tests/megaphone_ready_test.lua`,
`lua tests/megaphone_test.lua` e os testes existentes de cache, estado de morte,
PTT e mute. Os natives são simulados. Execute também
`node --test tests/megaphone_monitor_test.mjs` para permissão, retorno local,
descarte de respostas atrasadas e liberação dos dispositivos, sem microfone real.

Os testes simulam preferências, listas de tons, comandos, liberação da corneta/manual,
entrada/saída dos dois bancos da frente, bloqueio de traseiros/garupa, helicópteros,
migração de propriedade, comandos de sessões antigas, corneta simultânea,
manutenção com estado em cache, trabalho de interface em repouso e limpeza de áudio.
Os testes de navegador verificam botões, memórias, protocolo NUI, fundo
transparente, formulário ADMIN, revisões concorrentes e resolução 1280×720.
O teste de política global simula permissões, KVP, falhas de escrita, limites,
perda de permissão e recuperação após reiniciar, sem alterar dados da cidade.
Os testes Lua também cobrem as quatro combinações de luz/som ao sair e a recuperação
de uma reprodução encerrada, sem reiniciar sons saudáveis nem perpetuar sirene manual.

Antes de liberar no servidor, valide no FiveM com duas pessoas:

1. Q/Alt/R/E, cliques e soltura dos botões MAN/HORN.
2. Som e luzes vistos/ouvidos pelo segundo jogador.
3. As quatro combinações de persistência ao sair e voltar.
4. Entrada/saída rápida de piloto/copiloto, um deles saindo enquanto o outro fica,
   troca para banco traseiro e ambos segurando/soltando a corneta.
5. Viaturas comuns, motos (piloto permitido/garupa bloqueada), helicóptero policial,
   ambulâncias e modelos com sons adicionais.
6. Os presets após reconectar/reiniciar o recurso e as teclas remapeadas.
7. Outros recursos de HUD/NUI para conferir posição/foco.
8. Dirigir com Ctrl esquerdo e `/sirene ajustar`: W/S/A/D e Espaço, cliques da
   sirene, arrastar/redimensionar e fechar por Ctrl/Esc; repetir em helicóptero.
9. ADMIN: salvar, conferir com outro administrador/jogador, reiniciar Forge
   Siren, entrar novamente e testar volumes/alcance com dois jogadores. Usar
   fones para avaliar o timbre e impedir realimentação do retorno local.

Testes de navegador e simulações não substituem a validação do áudio nativo,
do streaming e da replicação OneSync no jogo.

## Créditos e licença

- AvarianKnight: criador original do PMA Sirensync.
- BerkieBb: manutenção do PMA Sirensync.
- Renewed Scripts / FjamZoo: refatoração usada como base.
- Forge: integração PR Bridge e controlador Svelte.

Licença MIT original preservada em `LICENSE`.
