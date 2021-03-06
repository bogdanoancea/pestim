#' @title Mode of the posterior density function of the lambda parameter.
#'
#' @description Compute the mode of the unnormalized posterior density function of the parameter
#' \eqn{\lambda} in the hierarchical model to estimate population counts.
#'
#' @param nMNO, nReg non-negative integer vectors with the number of individuals detected in each
#' cell according to the network operator and the register
#'
#' @param fu, fv named lists with the prior marginal distributions of the two-dimensional points
#' for the Monte Carlo integration
#'
#' @param flambda named list with the prior distribution of the lambda parameter
#'
#' @param relTol relative tolerance in the computation of the \code{\link{kummer}} function. Default
#' value is \code{1e-6}
#'
#' @param nSim number of two-dimensional points to generate to compute the integral. Default value
#' is \code{1e4}
#'
#' @param nStrata integer vector of length 2 with the number of strata in each dimension. Default
#' value is \code{c(1, 1e2)}
#'
#' @param verbose logical (default \code{FALSE}) to report progress of the computation
#'
#' @param nThreads number (default the number of all cores, including logical cores) to use for computation
#'
#' @return \code{modeLambda} returns a vector with the values of the mode of the density function
#' (column \code{probLambda}) for each cell.
#'
#' @details The lengths of the input vectors \code{nMNO} and \code{nReg} must be equal. Currently
#' the optimization algorithm is a simple direct algorithm taking into account the form of the
#' density function.
#'
#' The prior distributions are specified as named lists where the first component of each list must
#' be the name of distribution ('unif', 'triang', 'degen', 'gamma') and the rest components must be
#' named according to the name of the parameters of the random generator of the corresponding
#' distribution according to:
#'
#'   \itemize{
#'
#'     \item unif: \code{xMin}, \code{xMax} for the minimum, maximum of the sampled interval.
#'     \item degen: \code{x0} for the degenerate value of the random variable.
#'     \item triang: \code{xMin}, \code{xMax}, \code{xMode} for minimum, maximum and mode (see
#'     \code{\link{qtriang}}).
#'     \item gamma: \code{scale} and \code{shape} with the same meaning as in \code{\link{rgamma}}.
#'   }
#'
#' @seealso \code{\link{dlambda}} for the function to maximize.
#'
#' @examples
#' # This data.table must have 5x3= 15 rows
#' modeLambda(nMNO = c(20, 17, 25), nReg = c(115, 123, 119),
#'         fu = list(list('unif', xMin = 0.3, xMax = 0.5),
#'                   list('unif', xMin = 0.35, xMax = 0.45),
#'                   list('unif', xMin = 0.25, xMax = 0.43)),
#'         fv = list(list('gamma', shape = 11, scale = 12),
#'                   list('gamma', shape = 12, scale = 12.3),
#'                   list('gamma', shape = 13, scale = 11.5)),
#'         flambda = list(list('gamma', shape = 11, scale = 12),
#'                        list('gamma', shape = 12, scale = 12.3),
#'                        list('gamma', shape = 13, scale = 12)))
#'
#' @include dlambda.R
#'
#' @import data.table
#'
#' @export
modeLambda <- function(nMNO, nReg, fu, fv, flambda, relTol = 1e-6, nSim = 1e4, nStrata = c(1, 1e2), verbose = FALSE, nThreads = RcppParallel::defaultNumThreads()){

  nCells <- length(nMNO)
  if (length(nReg) != nCells) stop('nReg and nMNO must have the same length.')

  mc <- match.call()
  mc[[1L]] <- NULL

  if (nCells == 1) {
    if (verbose) cat('Searching maximum...\n')

    ak <- max((nMNO + nReg)/4, 0)
    bk <- (3*nMNO + 3*nReg)/4
    lk <- ak + (1 - (sqrt(5) - 1)/2)*(bk - ak)
    mk <- ak + ((sqrt(5) - 1)/2)*(bk - ak)

    val <- c(ak, lk, mk, bk)
    fval <- dlambda(c(ak,lk,mk,bk), nMNO, nReg, fu, fv, flambda, relTol, nSim, nStrata, verbose, nThreads)$probLambda

    stopCrit <- FALSE

    while (!stopCrit){

      index.max <- which.max(fval[2:3])

      if (index.max == 1){
        val <- c(val[1], val[1] + (1 - (sqrt(5) - 1)/2)*(val[3] - val[1]),val[2], val[3])
        fval <- c(fval[1],
                  dlambda(val[1] + (1 - (sqrt(5) - 1)/2)*(val[3] - val[1]),
                          nMNO, nReg, fu, fv, flambda, relTol, nSim, nStrata, verbose, nThreads)$probLambda,
                  fval[2], fval[3])

        diff <- abs(fval[3:4] - fval[c(1,3)])
        stopCrit <- any(diff <= fval[3] * relTol) | any(val[3:4]-val[c(1,3)] < 1e-8)
        xMax <- val[3]

      } else if (index.max == 2){
        val <- c(val[2], val[3],val[2] + ((sqrt(5) - 1)/2)*(val[4] - val[2]), val[4])
        fval <- c(fval[2], fval[3],
                  dlambda(val[2] + ((sqrt(5) - 1)/2)*(val[4] - val[2]),
                          nMNO, nReg, fu, fv, flambda, relTol, nSim, nStrata, verbose, nThreads)$probLambda,
                  fval[4])

        diff <- abs(fval[c(2,4)] - fval[1:2])
        stopCrit <- any(diff <= fval[2] * relTol) | any(val[c(2,4)]-val[1:2] < 1e-8)
        xMax <- val[2]

      }
    }
    return(xMax)
  } else {

    output <- sapply(seq(along = nMNO), function(i){

      if (verbose) cat(paste0('Computing for cell ', i, '...\n'))
      locnMNO <- nMNO[i]
      locnReg <- nReg[i]
      locfu.Pars <- lapply(fu[-1], '[', i)
      locfu <- c(fu[[1L]], locfu.Pars)
      locfv.Pars <- lapply(fv[-1], '[', i)
      locfv <- c(fv[[1L]], locfv.Pars)
      locflambda.Pars <- lapply(flambda[-1], '[', i)
      locflambda <- c(flambda[[1L]], locflambda.Pars)
      locMode <- modeLambda(locnMNO, locnReg, locfu, locfv, locflambda, relTol, nSim, nStrata, verbose, nThreads)
      if (verbose) cat(' ok.\n')
      return(locMode)
    })
    return(output)

  }
}
