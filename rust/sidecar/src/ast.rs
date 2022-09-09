use std::fmt::{self, Display, Formatter};

use sqlite3_parser::ast::{
  ColumnConstraint, ColumnDefinition, CreateTableBody, Expr, Name, NamedTableConstraint,
  QualifiedName, TableConstraint, ToTokens,
};

// TODO: push down to name struct or add there as well
pub trait QualifiedNameExt {
  fn to_view_ident(&self) -> String;
  fn to_patch_view_ident(&self) -> String;
  fn to_crr_table_ident(&self) -> String;
  fn to_crr_clock_table_ident(&self) -> String;
  fn to_insert_trig_ident(&self) -> String;
  fn to_update_trig_ident(&self) -> String;
  fn to_delete_trig_ident(&self) -> String;
  fn to_patch_trig_ident(&self) -> String;
  fn to_ident(&self) -> String;
}

pub trait NameExt {
  fn to_view_ident(&self) -> String;
  fn to_patch_view_ident(&self) -> String;
  fn to_crr_table_ident(&self) -> String;
  fn to_crr_clock_table_ident(&self) -> String;
  fn to_insert_trig_ident(&self) -> String;
  fn to_update_trig_ident(&self) -> String;
  fn to_delete_trig_ident(&self) -> String;
  fn to_patch_trig_ident(&self) -> String;
  fn to_ident(&self) -> String;
  fn to_naked(&self) -> String;
}

pub trait CreateTableBodyExt {
  fn non_crr_columns(&self) -> Result<Vec<&ColumnDefinition>, &'static str>;
}

pub trait ColumnDefinitionExt {
  fn is_primary_key(&self, table_constraints: &Option<Vec<NamedTableConstraint>>) -> bool;
}

impl QualifiedNameExt for QualifiedName {
  fn to_view_ident(&self) -> String {
    QualifiedNameExt::to_ident(self)
  }

  fn to_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!("{}.{}", db_name.to_ident(), self.name.to_ident()),
      None => self.name.to_ident(),
    }
  }

  fn to_patch_view_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!("{}.{}", db_name.to_ident(), self.name.to_patch_view_ident()),
      None => self.name.to_patch_view_ident(),
    }
  }

  fn to_crr_table_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!("{}.{}", db_name.to_ident(), self.name.to_crr_table_ident()),
      None => self.name.to_crr_table_ident(),
    }
  }

  fn to_crr_clock_table_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!(
        "{}.{}",
        db_name.to_ident(),
        self.name.to_crr_clock_table_ident()
      ),
      None => self.name.to_crr_clock_table_ident(),
    }
  }

  fn to_insert_trig_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!(
        "{}.{}",
        db_name.to_ident(),
        self.name.to_insert_trig_ident()
      ),
      None => self.name.to_insert_trig_ident(),
    }
  }

  fn to_update_trig_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!(
        "{}.{}",
        db_name.to_ident(),
        self.name.to_update_trig_ident()
      ),
      None => self.name.to_update_trig_ident(),
    }
  }

  fn to_delete_trig_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!(
        "{}.{}",
        db_name.to_ident(),
        self.name.to_delete_trig_ident()
      ),
      None => self.name.to_delete_trig_ident(),
    }
  }

  fn to_patch_trig_ident(&self) -> String {
    match &self.db_name {
      Some(db_name) => format!("{}.{}", db_name.to_ident(), self.name.to_patch_trig_ident()),
      None => self.name.to_patch_trig_ident(),
    }
  }
}

impl NameExt for Name {
  fn to_ident(&self) -> String {
    format!("\"{}\"", self.to_naked())
  }

  fn to_view_ident(&self) -> String {
    NameExt::to_ident(self)
  }

  fn to_patch_view_ident(&self) -> String {
    format!("\"cfsql_patch__{}\"", self.to_naked())
  }

  fn to_crr_table_ident(&self) -> String {
    format!("\"cfsql_crr__{}\"", self.to_naked())
  }

  fn to_crr_clock_table_ident(&self) -> String {
    format!("\"cfsql_clock__{}\"", self.to_naked())
  }

  fn to_insert_trig_ident(&self) -> String {
    format!("\"cfsql_ins_trig__{}\"", self.to_naked())
  }

  fn to_update_trig_ident(&self) -> String {
    format!("\"cfsql_up_trig__{}\"", self.to_naked())
  }

  fn to_delete_trig_ident(&self) -> String {
    format!("\"cfsql_del_trig__{}\"", self.to_naked())
  }

  fn to_patch_trig_ident(&self) -> String {
    format!("\"cfsql_patch_trig__{}\"", self.to_naked())
  }

  fn to_naked(&self) -> String {
    self.0.replace(&['[', '"', ']', '`'][..], "")
  }
}

impl CreateTableBodyExt for CreateTableBody {
  fn non_crr_columns(&self) -> Result<Vec<&ColumnDefinition>, &'static str> {
    match self {
      Self::ColumnsAndConstraints { columns, .. } => Ok(
        columns
          .iter()
          .filter(|x| !x.col_name.0.contains("__cfsql"))
          .collect::<Vec<_>>(),
      ),
      _ => Err("table creation from select is not supported for crr creation"),
    }
  }
}

impl ColumnDefinitionExt for ColumnDefinition {
  fn is_primary_key(&self, table_constraints: &Option<Vec<NamedTableConstraint>>) -> bool {
    self.constraints.iter().any(|c| match c.constraint {
      ColumnConstraint::PrimaryKey { .. } => true,
      _ => false,
    }) || (table_constraints.is_some()
      && table_constraints
        .as_ref()
        .unwrap()
        .iter()
        .any(|c| match &c.constraint {
          TableConstraint::PrimaryKey { columns, .. } => {
            columns.len() == 1
              && match &columns[0].expr {
                // TODO: we probably need to to_naked compare?
                Expr::Id(id) => id.0 == self.col_name.0,
                _ => false,
              }
          }
          _ => false,
        }))
  }
}

pub struct WrapForDisplay<T: ToTokens> {
  pub val: T,
}

impl<T: ToTokens> Display for WrapForDisplay<T> {
  fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
    self.val.to_fmt(f)
  }
}

pub fn to_string<T: ToTokens>(x: T) -> String {
  format!("{}", WrapForDisplay { val: x })
}

pub fn wrap_for_display<T: ToTokens>(x: T) -> WrapForDisplay<T> {
  WrapForDisplay { val: x }
}

#[cfg(test)]
mod tests {
  use fallible_iterator::FallibleIterator;
  use sqlite3_parser::{
    ast::{Cmd, Stmt},
    lexer::sql::Parser,
  };

  use super::QualifiedNameExt;

  #[test]
  fn test_parsed_to_ident() {
    let sql = "CREATE TABLE [foo] (a, b)";
    let mut parser = Parser::new(sql.as_bytes());

    let cmd = parser.next().unwrap().unwrap();
    match cmd {
      Cmd::Stmt(Stmt::CreateTable { tbl_name, .. }) => {
        assert_eq!(tbl_name.to_ident(), "\"foo\"")
      }
      _ => unreachable!(),
    }
  }
}