diff_align <- function(diff, x, y) {
  n <- nrow(diff)

  x_out <- character()
  y_out <- character()
  x_idx <- integer()
  y_idx <- integer()

  for (i in seq_len(n)) {
    row <- diff[i, , drop = FALSE]
    x_i <- seq2(row$x1, row$x2)
    y_i <- seq2(row$y1, row$y2)

    # Sometimes (last row?) a change is really one change + many additions
    if (row$t == "c" && length(x_i) != length(y_i)) {
      m <- max(length(x_i), length(y_i))
      length(x_i) <- m
      length(y_i) <- m
    }

    x_out <- c(x_out, switch(row$t,
      a = c(col_x(x[x_i]), NA[y_i]),
      c = col_c(x[x_i]),
      d = col_a(x[x_i]),
      x = col_x(x[x_i])
    ))
    y_out <- c(y_out, switch(row$t,
      a = col_d(y[y_i]),
      c = col_c(y[y_i]),
      d = c(col_x(y[y_i]), NA[x_i]),
      x = col_x(y[y_i])
    ))

    x_idx <- c(x_idx, x_i[x_i != 0], if (row$t == "a") NA[y_i])
    y_idx <- c(y_idx, y_i[y_i != 0], if (row$t == "d") NA[x_i])
  }

  # Ensure both contexts are same length
  if (length(x_out) != length(y_out)) {
    # TODO: need to figure out when to truncate from left vs right
    len <- min(length(x_out), length(y_out))
    x_out <- x_out[seq(length(x_out) - len + 1, length(x_out))]
    y_out <- y_out[seq(length(y_out) - len + 1, length(y_out))]

    x_idx <- x_idx[seq(length(x_idx) - len + 1, length(x_idx))]
    y_idx <- y_idx[seq(length(y_idx) - len + 1, length(y_idx))]
  }

  x_slice <- make_slice(x, x_idx)
  y_slice <- make_slice(y, y_idx)

  list(
    x = x_out,
    y = y_out,
    x_slice = x_slice,
    y_slice = y_slice,
    x_idx = x_idx,
    y_idx = y_idx
  )
}

# Only want to show slice if it's partial
make_slice <- function(x, idx) {
  if (all(is.na(idx))) {
    return(NULL)
  }

  idx <- range(idx, na.rm = TRUE)
  if (idx[[1]] <= 1 && idx[[2]] >= length(x)) {
    NULL
  } else {
    idx
  }
}

col_a <- function(x) ifelse(is.na(x), NA, cli::col_blue(x))
col_d <- function(x) ifelse(is.na(x), NA, cli::col_yellow(x))
col_c <- function(x) ifelse(is.na(x), NA, cli::col_green(x))
col_x <- function(x) ifelse(is.na(x), NA, cli::col_grey(x))


# values ------------------------------------------------------------------

diff_element <- function(x, y, paths = c("x", "y"),
                         quote = "\"", justify = "left",
                         width = getOption("width"),
                         ci = in_ci()) {
  if (!is.null(quote)) {
    x <- encodeString(x, quote = quote)
    y <- encodeString(y, quote = quote)
  }

  diff <- ses_context(x, y)
  if (length(diff) == 0) {
    return(new_compare())
  }

  format <- lapply(diff, format_diff_matrix,
    x = x,
    y = y,
    paths = paths,
    justify = justify,
    width = width,
    ci = ci
  )
  new_compare(unlist(format, recursive = FALSE))
}

format_diff_matrix <- function(diff, x, y, paths,
                               justify = "left",
                               width = getOption("width"),
                               ci = in_ci()) {
  alignment <- diff_align(diff, x, y)
  mat <- rbind(alignment$x, alignment$y)
  mat[is.na(mat)] <- ""

  n_trunc <- if (ci) 0 else ncol(mat) - 10

  # Label slices, if needed
  x_path_label <- label_path(paths[[1]], alignment$x_slice)
  y_path_label <- label_path(paths[[2]], alignment$y_slice)

  # Paired lines ---------------------------------------------------------------
  mat_out <- cbind(paste0("`", c(x_path_label, y_path_label), "`:"), mat)
  if (n_trunc > 0) {
    mat_out <- mat_out[, 1:11]
    mat_out <- cbind(mat_out, c(paste0("and ", n_trunc, " more..."), "..."))
  }
  out <- apply(mat_out, 2, fansi_align, justify = justify)
  rows <- apply(out, 1, paste, collapse = " ")

  if (fansi::nchar_ctl(rows[[1]]) <= width) {
    return(paste0(rows, collapse = "\n"))
  }

  # Side-by-side ---------------------------------------------------------------
  x_idx_out <- label_idx(alignment$x_idx)
  y_idx_out <- label_idx(alignment$y_idx)
  idx_width <- max(nchar(x_idx_out), nchar(y_idx_out))

  divider <- ifelse(mat[1,] == mat[2, ], "|", "-")

  mat_out <- cbind(c(paths[[1]], "|", paths[[2]]), rbind(mat[1, ], divider, mat[2, ]))
  if (n_trunc > 0) {
    mat_out <- mat_out[, 1:11]
    mat_out <- cbind(mat_out, c("...", "", "..."))
    x_idx_out <- c(x_idx_out[1:10], "...")
    y_idx_out <- c(y_idx_out[1:10], paste0("and ", n_trunc, " more ..."))
  }
  mat_out <- rbind(
    format(c("", x_idx_out), justify = "right"),
    mat_out,
    format(c("", y_idx_out), justify = "left")
  )

  out <- apply(mat_out, 1, fansi_align, justify = "left")
  rows <- apply(out, 1, paste, collapse = " ")

  if (fansi::nchar_ctl(rows[[1]]) <= width) {
    return(paste0(rows, collapse = "\n"))
  }

  # Line-by-line ---------------------------------------------------------------

  lines <- character()

  line_a <- function(x) if (length(x) > 0) col_a(paste0("+ ", x))
  line_d <- function(x) if (length(x) > 0) col_d(paste0("- ", x))
  line_x <- function(x) if (length(x) > 0) col_x(paste0("  ", x))

  for (i in seq_len(nrow(diff))) {
    row <- diff[i, , drop = FALSE]
    x_i <- seq2(row$x1, row$x2)
    y_i <- seq2(row$y1, row$y2)
    lines <- c(lines, switch(row$t,
      x = line_x(x[x_i]),
      a = c(line_x(x[x_i]), line_d(y[y_i])),
      c = interleave(line_a(x[x_i]), line_d(y[y_i])),
      d = line_a(x[x_i])
    ))
  }

  n_trunc <- if (ci) 0 else length(lines) - (10 * 2)
  if (n_trunc > 0) {
    lines <- c(lines[1:20], paste0("and ", n_trunc, " more ..."))
  }

  paste0(
    paste0(x_path_label, " vs ", y_path_label), "\n",
    paste0(lines, collapse = "\n")
  )
}

interleave <- function(x, y) {
  ord <- c(seq_along(x), seq_along(y))
  c(x, y)[order(ord)]
}

label_path <- function(path, slice) {
  if (is.null(slice)) {
    path
  } else {
    paste0(path, "[", slice[[1]], ":", slice[[2]], "]")
  }
}

label_idx <- function(idx) {
  ifelse(is.na(idx), "", paste0("[", idx, "]"))
}
