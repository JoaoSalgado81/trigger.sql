--exc 1

create table estoque (
id serial primary key,
nome_item varchar(100) not null,
quantidade int not null default 0
)

create or replace function fn_valida_estoque_minimo() -- cria ou substitui uma função
returns trigger as $$ -- retorno especial para gatilho
begin
if  NEW.quantidade 	< 0 then
RAISE EXCEPTION 'Operação cancelada! O item "%" não pode ter estoque negativo (Tentativa: % unidade(s)).', --se for menor que zero cancela
NEW.nome_item, NEW.quantidade; --atualizações
end if;
return new;
end;
$$ language plpgsql;

create trigger trg_valida_estoque
before insert or update on estoque
for each row
execute function fn_valida_estoque_minimo();

--exc 2

create table contas (
id serial primary key,
cliente varchar(100) not null,
saldo numeric(10,2) not null default 0.00
)

create table movimentacoes (
id serial primary key,
conta_id int references contas(id),
tipo varchar(1) check (tipo in ('c', 'd')),
valor numeric(10,2) not null, 
 data_movimentacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

create or replace function fn_atualiza_saldo_conta()
returns trigger as $$ -- retorno especial para gatilho
begin 
if NEW.tipo = 'c' then
update contas set saldo = saldo + NEW.valor where id = NEW.conta_id;
elsif NEW.tipo = 'd' then
update contas set saldo = saldo - NEW.valor where id = NEW.conta_id;
end if;
return new;
end;
$$ language plpgsql;

create trigger  trg_atualiza_saldo
after insert on movimentacoes --after porque se a inserção da movimentação falhar por qualquer motivo, o saldo não deve ser alterado.
for each row
execute function fn_atualiza_saldo_conta();

--exc 3

create table funcionarios (
    id serial primary key,
    nome varchar(100) not null,
    cargo varchar(50) not null,
    salario numeric(10, 2) not null
);

create table historico_carreira (
    id serial primary key,
    funcionario_id int not null,
    cargo_antigo varchar(50),
    cargo_novo varchar(50),
    salario_antigo numeric(10, 2),
    salario_novo numeric(10, 2),
    data_alteracao timestamp default current_timestamp
);

create or replace function fn_log_alteracao_carreira()
returns trigger as $$ -- retorno especial para gatilho
begin
    if old.cargo is distinct from new.cargo or old.salario is distinct from new.salario then --aqui atualiza o antigo pro novo
        insert into historico_carreira (funcionario_id, cargo_antigo, cargo_novo, salario_antigo, salario_novo)
        values (old.id, old.cargo, new.cargo, old.salario, new.salario); --aqui atribui os valores
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_log_carreira
after update on funcionarios --after porque se falhar por qualquer motivo, o saldo não deve ser alterado.
for each row
execute function fn_log_alteracao_carreira();

--exc 4

create table clientes (
    id serial primary key,
    nome varchar(100) not null,
    email varchar(100) not null,
    ativo boolean default true
);

create table clientes_deletados_log (
    id serial primary key,
    cliente_id int,
    nome varchar(100),
    email varchar(100),
    data_remocao timestamp default current_timestamp
);

create or replace function fn_soft_delete_cliente()
returns trigger as $$
begin
   
    insert into clientes_deletados_log (cliente_id, nome, email)
    values (old.id, old.nome, old.email);

    update clientes set ativo = false where id = old.id; --oculta os clientes "deletados" e apenas faz pesquisar por ativos

    return null; --retornar NULL em um trigger BEFORE DELETE cancela a remoção física da linha, mantendo o registro no banco.
end;
$$ language plpgsql;

create trigger trg_soft_delete_cliente
before delete on clientes
for each row
execute function fn_soft_delete_cliente();

--exc 5

create table reservas (
id serial primary key,
numero_quarto int not null,
data_checkin date not null,
data_checkout date not null,
valor_diaria numeric(10,2) not null,
valor_total numeric(10,2)
)

create or replace function fn_processa_reserva() -- Cria ou atualiza a função
returns trigger as $$ 
declare 
    dias_estadia int; -- Variável para guardar a quantidade de dias
begin -- Começa os comandos da função

    if new.data_checkout <= new.data_checkin then -- Se a saída for no mesmo dia ou antes da entrada
        raise exception 'A data de check-out (%) precisa ser posterior à data de check-in (%)!', -- Exibe erro e cancela a ação
        new.data_checkout, new.data_checkin;
    end if; -- Fim da checagem de datas
    
    new.valor_total := dias_estadia * new.valor_diaria; -- Calcula o valor total multiplicando dias pela diária

    return new; -- Salva os dados validados
end; -- Fim do código da função
$$ language plpgsql; -- Define a linguagem do código

create trigger trg_processa_reserva -- Cria o gatilho
before insert or update on reservas -- Ativa ANTES de inserir ou alterar na tabela reservas
for each row -- Roda para cada linha modificada
execute function fn_processa_reserva(); -- Chama a função que criamos acima

--exc 6

create table pedidos (
    id serial primary key,
    cliente varchar(100) not null,
    valor_total numeric(10, 2) not null default 0.00,
    data_criacao timestamp default CURRENT_TIMESTAMP
);

CREATE TABLE itens_pedido (
   id serial primary key,
    pedido_id int references pedidos(id) ON DELETE CASCADE,
    produto_nome varchar(100) not null,
    quantidade int not null,
    preco_unitario numeric(10, 2) not null
);

create or replace function fn_recalcula_total_pedido()
returns trigger as $$ 
declare
    v_pedido_id int; -- Variável para guardar o ID do pedido
begin -- Começa os comandos

    if (tg_op = 'DELETE') then -- Se a ação foi apagar um item
        v_pedido_id := old.pedido_id; -- Pega o ID do pedido que já existia
    else
        v_pedido_id := new.pedido_id; -- Pega o ID do novo pedido
    end if; -- Fim do if

    update pedidos 
    set valor_total = coalesce(( -- Ajusta o valor total (se der vazio, usa 0.00)
        select sum(quantidade * preco_unitario) -- Soma a quantidade × preço de cada item
        from itens_pedido -- Consulta os itens
        where pedido_id = v_pedido_id -- Filtra apenas pelo pedido atual
    ), 0.00)
    where id = v_pedido_id; -- Aplica a alteração no pedido certo

    if (tg_op = 'DELETE') then -- Se o item foi apagado
        return old; -- Confirma a remoção do item antigo
    end if;
    return new; -- Confirma a gravação do novo item
end; -- Fim da função
$$ language plpgsql; -- Define a linguagem do código

create trigger trg_atualiza_total_pedido -- Cria o gatilho
after insert or update or delete on itens_pedido -- Ativa DEPOIS de inserir, alterar ou apagar itens
for each row 
execute function fn_recalcula_total_pedido(); -- Chama a função para refazer a soma do pedido

--exc 7

create table produtos (
    id serial primary key,
    nome varchar(100) not null,
    estoque_atual int not null default 0
);


create table itens_venda (
    id serial primary key,
    produto_id int references produtos(id),
    quantidade_vendida int not null,
    data_venda timestamp default current_timestamp
);


create or replace function fn_processa_baixa_estoque() -- Cria ou atualiza a função de dar baixa
returns trigger as $$ 
declare
    v_estoque_atual int; -- Variável para guardar o estoque atual
    v_nome_produto varchar(100); -- Variável para guardar o nome do produto
begin 

    select estoque_atual, nome into v_estoque_atual, v_nome_produto -- Busca estoque e nome do produto
    from produtos
    where id = new.produto_id; -- Procura pelo produto que está sendo vendido

    if not found then -- Se o produto não existir no banco
        raise exception 'Produto com ID % não encontrado!', new.produto_id; -- Cancela e exibe aviso
    end if;

    if v_estoque_atual < new.quantidade_vendida then -- Se o estoque for menor do que a venda
        raise exception 'Estoque insuficiente para o produto "%". Disponível: %, Solicitado: %.', -- Cancela e mostra erro de falta de estoque
            v_nome_produto, v_estoque_atual, new.quantidade_vendida;
    end if;

    update produtos 
    set estoque_atual = estoque_atual - new.quantidade_vendida -- Tira da quantidade em estoque o que foi vendido
    where id = new.produto_id; -- No produto correto

    return new; -- Salva a venda normalmente
end; -- Fim da função
$$ language plpgsql; -- Define a linguagem do código

create trigger trg_baixa_estoque_venda -- Cria o gatilho
before insert on itens_venda -- Ativa ANTES de registrar a venda
for each row -- Roda para cada item vendido
execute function fn_processa_baixa_estoque(); -- Chama a função que dá baixa no estoque

--exc 8

create table projetos (
    id serial primary key,
    nome_projeto varchar(100) not null,
    status varchar(20) default 'em andamento'
);

create table tarefas (
    id serial primary key,
    projeto_id int references projetos(id) on delete cascade,
    descricao varchar(200) not null,
    status varchar(20) default 'pendente'
);

create or replace function fn_propaga_cancelamento_projeto() 
returns trigger as $$ 
begin

    if new.status = 'cancelado' and old.status is distinct from 'cancelado' then -- Se o projeto mudou para 'cancelado'
        
        update tarefas -- Atualiza as tarefas
        set status = 'cancelada' -- Muda o status da tarefa para 'cancelada'
        where projeto_id = new.id and status = 'pendente'; -- Apenas tarefas pendentes desse projeto
        
    end if; -- Fim da checagem do status
    
    return new; -- Salva as alterações do projeto
end; -- Fim da função
$$ language plpgsql; -- Define a linguagem do código

create trigger trg_cancela_tarefas_projeto -- Cria o gatilho na tabela projetos
after update on projetos -- Ativa DEPOIS de alterar um projeto
for each row 
execute function fn_propaga_cancelamento_projeto(); -- Chama a função para cancelar as tarefas