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
returns trigger as $$
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
after insert on movimentacoes
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
returns trigger as $$
begin
    if old.cargo is distinct from new.cargo or old.salario is distinct from new.salario then
        insert into historico_carreira (funcionario_id, cargo_antigo, cargo_novo, salario_antigo, salario_novo)
        values (old.id, old.cargo, new.cargo, old.salario, new.salario);
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_log_carreira
after update on funcionarios
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

    update clientes set ativo = false where id = old.id;

    return null;
end;
$$ language plpgsql;

create trigger trg_soft_delete_cliente
before delete on clientes
for each row
execute function fn_soft_delete_cliente();