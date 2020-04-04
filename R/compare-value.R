compare_value <- function(x, y, path = "x", tolerance = .Machine$double.eps^0.5) {
  attributes(x) <- NULL
  attributes(y) <- NULL

  if (is.numeric(x)) {
    if (num_equal(x, y, tolerance)) {
      return(new_compare())
    }

    x_cmp <- num_format(x)
    y_cmp <- num_format(y)
  } else if (is.character(x)) {
    x_cmp <- encodeString(x, quote = "'")
    y_cmp <- encodeString(y, quote = "'")
  } else {
    x_cmp <- x
    y_cmp <- y
  }

  diff <- ses(x_cmp, y_cmp)
  if (nrow(diff) == 0) {
    if (is.numeric(x)) {
      xi <- seq_along(x)
      diff <- ses_df(xi, xi, "c", xi, xi)[x != y, , drop = FALSE]
      x_cmp <- num_format(y - x)
      y_cmp <- rep(0, length(x))
      path <- glue("\u0394{path}")
    } else {
      return(new_compare())
    }
  }
  diffs <- diff_split(diff, n = length(x))
  new_compare(map_chr(diffs, continguous_diff, x = x_cmp, y = y_cmp, path = path))
}

diff_split <- function(diff, n) {
  diff$start <- pmax(diff$x1 - 3, 1)
  diff$end <- pmin(diff$x2 + 3, n)

  new_group <- c(TRUE, diff$start[-1] > diff$end[-nrow(diff)])
  group_id <- cumsum(new_group)
  split(diff, group_id)
}

continguous_diff <- function(diff, x, y, path) {
  n <- nrow(diff)
  start <- diff$start[[1]]
  end <- diff$end[[n]]

  out <- character()
  idx <- start
  for (i in seq_len(n)) {
    row <- diff[i, , drop = FALSE]
    if (idx < row$x1) {
      out <- c(out, x[idx:(row$x1 - 1)])
    }

    x_i <- row$x1:row$x2
    y_i <- row$y1:row$y2

    out <- c(out, switch(row$t,
      a = c(x[x_i], change_add(y[y_i])),
      c = change_modify(x[x_i], y[y_i]),
      d = change_delete(x[x_i])
    ))
    idx <- row$x2 + 1
  }

  if (idx <= end) {
    out <- c(out, x[idx:end])
  }

  if (start != 1 || end != length(x)) {
    if (start != 1) {
      out <- c("...", out)
    }
    if (end != length(x)) {
      out <- c(out, "...")
    }
    path <- glue("{path}[{start}:{end}]")
  }

  out <- paste(out, collapse = " ")
  glue("`{path}`: {out}")
}

change_add <- function(x) {
  cli::col_blue("+", x)
}

change_modify <- function(x, y) {
  paste0(cli::col_yellow(x), "/", cli::col_blue(y))
}

change_delete <- function(x) {
  cli::col_yellow("-", x)
}
