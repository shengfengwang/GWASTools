
.checkVars <- function(variables, col.nums, col.total, intensity.vars) {
    stopifnot(all(variables %in% c("genotype", intensity.vars)))

    ## check col.nums
    col.nums <- col.nums[!is.na(col.nums)]
    if(!all(names(col.nums) %in% c("snp", "sample", "geno", "a1", "a2", intensity.vars))) stop("problem with col.nums vector names")
    if(!is.integer(col.nums)) stop("col.nums vector class is not integer")
    if(!("snp" %in% names(col.nums))) stop("snp id missing in col.nums")
    if( max(col.nums) > col.total) stop("some element of col.nums is greater than total number of columns")

    ## compare with variables
    chk.vars <- intersect(names(col.nums), intensity.vars)
    if (length(chk.vars) > 0) {
        if(!all(is.element(chk.vars, variables))) stop("mismatch between col.nums and variables")
    }
    if(any(is.element(names(col.nums), c("geno", "a1", "a2"))) & !is.element("genotype",variables)) stop("mismatch between col.nums and variables")
}

.checkSnpAnnotation <- function(snp.annotation, variables="", allele.coding="") {
    ## check that snp annotation has right columns
    stopifnot(all(c("snpID", "chromosome", "position", "snpName") %in% names(snp.annotation)))
    if ("genotype" %in% variables & allele.coding == "nucleotide") {
        if (!(all(c("alleleA", "alleleB") %in% names(snp.annotation)))) {
            stop("alleleA and alleleB are required in snp.annotation for allele.coding=nucleotide")
        }
    }

    ## make sure all snp annotation columns are integers
    if (!is(snp.annotation$snpID, "integer")) {
        snp.annotation$snpID <- as.integer(snp.annotation$snpID)
        warning(paste("coerced snpID to type integer"))
    }
    if (!is(snp.annotation$chromosome, "integer")) {
        snp.annotation$chromosome <- as.integer(snp.annotation$chromosome)
        warning(paste("coerced chromosome to type integer"))
    }
    if (!is(snp.annotation$position, "integer")) {
        snp.annotation$position <- as.integer(snp.annotation$position)
        warning(paste("coerced position to type integer"))
    }

    ## make sure snpID is unique
    stopifnot(length(snp.annotation$snpID) == length(unique(snp.annotation$snpID)))

    ## make sure snpID is sorted by chromsome and position
    stopifnot(all(snp.annotation$snpID == sort(snp.annotation$snpID)))
    sorted <- order(snp.annotation$chromosome, snp.annotation$position)
    if (!all(snp.annotation$snpID == snp.annotation$snpID[sorted])) {
        stop("snpID is not sorted by chromosome and position")
    }
}

.mapAlleles <- function(dat, allele.map) {
    if ("geno" %in% names(dat)) {
        dat$a1 <- substr(dat$geno,1,1)
        dat$a2 <- substr(dat$geno,2,2)
        dat$geno <- NULL
    }
    a1.ab <- rep(NA, nrow(dat))
    a2.ab <- rep(NA, nrow(dat))
    for (allele in c("A", "B")) {
        a1.ab[dat$a1 == allele.map[,paste0("allele",allele)]] <- allele
        a2.ab[dat$a2 == allele.map[,paste0("allele",allele)]] <- allele
    }
    dat$a1 <- a1.ab
    dat$a2 <- a2.ab
    dat
}

## number of A alleles in the genotype, with missing = NA
.genoAsInt <- function(geno) {
    genotype <- rep(NA, length(geno))
    genotype[geno %in% "AA"] <- 2
    genotype[geno %in% c("AB", "BA")] <- 1
    genotype[geno %in% "BB"] <- 0
    genotype
}


createDataFile <- function(path=".",
                           filename,
                           file.type=c("gds", "ncdf"),
                           variables = "genotype",
                           snp.annotation,
                           scan.annotation,
                           sep.type,
                           skip.num,
                           col.total,
                           col.nums,
                           scan.name.in.file,
                           allele.coding = c("AB", "nucleotide"),
                           precision = "single",
                           compress = "ZIP_RA:8M",
                           compress.geno = "ZIP_RA",
                           compress.annot = "ZIP_RA",
                           array.name = NULL,
                           genome.build = NULL,
                           diagnostics.filename = "createDataFile.diagnostics.RData",
                           verbose = TRUE) {

    file.type <- match.arg(file.type)
    allele.coding <- match.arg(allele.coding)

    ## checks
    intensity.vars <-  c("quality", "X", "Y", "rawX", "rawY", "R", "Theta", "BAlleleFreq","LogRRatio")
    .checkVars(variables, col.nums, col.total, intensity.vars)
    .checkSnpAnnotation(snp.annotation, variables, allele.coding)
    stopifnot((c("scanID", "scanName", "file") %in% names(scan.annotation)))

    ## create data file
    if (file.type == "gds") {
        ## don't need n.samples since we will use append later
        ## get storage mode of samples
        storage.mode <- ifelse(is.character(scan.annotation$scanID), "character", "integer")
        genofile <- .createGds(snp.annotation, filename, variables, precision,
                               compress, compress.geno, compress.annot,
                               sample.storage=storage.mode)
    } else if (file.type == "ncdf") {
        if (any(is.na(as.integer(scan.annotation$scanID)))) {
            stop("integer scanID required for ncdf files")
        }
        genofile <- .createNcdf(snp.annotation, filename, variables, nrow(scan.annotation),
                                 precision, array.name, genome.build)
    }


    ## Input and check the genotypic data

    ## get sample id information
    sample.names <- scan.annotation$scanName
    sample.nums <- scan.annotation$scanID

    ## file names
    data.filenames <- file.path(path, scan.annotation$file)
    rm(scan.annotation)

    ## get snp information
    snp.names <- snp.annotation$snpName
    n <- nrow(snp.annotation)    
    if ("genotype" %in% variables & allele.coding == "nucleotide") {
        allele.map <- snp.annotation[,c("alleleA", "alleleB")]
        row.names(allele.map) <- snp.names
    }
    rm(snp.annotation)

    ## generate colClasses vector for read.table
    cc <- rep("NULL",col.total)
    cc[col.nums[names(col.nums) %in% c("snp","sample","geno","a1","a2")]] <- "character"
    cc[col.nums[names(col.nums) %in% intensity.vars]] <- "double"

    ## generate names for the genotype data.frame
    df.names <- names(sort(col.nums))

    ## set up objects to keep track of things for each file
    fn <- length(data.filenames)
    read.file <- rep(NA, fn)  # indicator of whether the file was readable or not
    row.num <- rep(NA, fn)	  # number of rows read
    samples <- vector("list",fn)	 # list of vectors of unique sample names in each file
    sample.match <- rep(NA, fn)	# indicator whether sample name inside file matches sample.names vector
    missg <- vector("list",fn)	 # vector of character string(s) used for missing genotypes (i.e. not AA, AB or BB)
    snp.chk <- rep(NA,fn)		# indicator for incorrect set of snp ids
    chk <- rep(NA,fn)		# indicator for final check on data ready to load into file
    ## when values for the indicators are assigned, a value of 1 means okay and 0 means not okay
    ## a value of NA means that file processing was aborted before that check was made

    ## add data to file one sample (file) at a time

    if (verbose) start <- Sys.time()	# to keep track of the rate of file processing
    for(i in 1:fn){

        ## save diagnostics for each sample in case of interruption
        diagnostics <- list(read.file, row.num, samples, sample.match, missg, snp.chk, chk)
        names(diagnostics) <- c("read.file", "row.num", "samples", "sample.match", "missg", "snp.chk", "chk")
        save(diagnostics, file=diagnostics.filename)

        ## read in the file for one sample and keep columns of interest; skip to next file if there is a read error (using function "try")
        if(scan.name.in.file == -1) {skip.num <- skip.num-1; head<-TRUE} else  {head<-FALSE}
        dat <- try(read.table(data.filenames[i], header=head, sep=sep.type, comment.char="", skip=skip.num, colClasses=cc))
        if (inherits(dat, "try-error")) { read.file[i] <- 0; message(paste("error reading file",i)); next }
        read.file[i] <- 1
        ## get sample name from column heading for Affy
        if(scan.name.in.file == -1) {tmp.names <- names(dat)}
        names(dat) <- df.names
        ##check and save row and sample number info
        row.num[i] <- dim(dat)[1]
        if(row.num[i] != n) {rm(dat); next}  # each file should have the same number of rows (one per snp)
        ## sample names for Illumina (i.e. a sample name column)
        if(is.element("sample", names(dat))){
            samples[[i]] <- unique(dat$sample)
            if(length(samples[[i]])>1) {rm(dat);next}	# there should only be one sample per file
            if(samples[[i]] != sample.names[i]) {sample.match[i] <- 0; rm(dat); next}  else {sample.match[i] <- 1}
            ## sample name inside file should match sample.name vector
        }
        ## sample names for Affy (one column label contains the sample name)
        if(scan.name.in.file == -1) {
            tmp <- paste(sample.names[i], c("_Call", "_Confidence",".cel"),sep="")
            if(!any(is.element(tmp, tmp.names))) {sample.match[i] <- 0; rm(dat); next} else {sample.match[i] <- 1}
        }	## sample name embedded in file name and column name within file should match
        ## check for duplicate snp names
        if(any(duplicated(dat$snp))) {snp.chk[i] <- 0; rm(dat); next}
        ## check that all expected snps are present and sort into int.id order
        if(any(!is.element(dat$snp, snp.names))) {snp.chk[i] <- 0; rm(dat); next} else snp.chk[i] <- 1
        dat <- dat[match(snp.names, dat$snp),]

        ## set non-finite values to missing
        for (v in intersect(names(dat), intensity.vars)) dat[[v]][!is.finite(dat[[v]])]<- NA

        if(any(is.element(c("geno","a1","a2"),names(dat)))){
            if (allele.coding == "nucleotide") {
                stopifnot(allequal(dat$snp, row.names(allele.map)))
                dat <- .mapAlleles(dat, allele.map)
            }
            ## make diploid genotypes if necessary
            if(!is.element("geno", names(dat)) && is.element("a1", names(dat)) && is.element("a2", names(dat))) {
                dat$geno <- paste0(dat$a1, dat$a2)
            }
            ## get character string(s) for missing genotypes
            missg[[i]] <- setdiff(dat$geno, c("AA","AB","BB"))
            ## Make genotypes numeric
            dat$genotype <- .genoAsInt(dat$geno)
        }

        ## Load data into file
        vars <- intersect(c("genotype", intensity.vars), names(dat))
        if (i == 1) message("adding variables: ", paste(vars, collapse=", "))
        .addData(genofile, vars, dat, sample.nums[i], i)

        chk[i] <- 1	# made it this far
        rm(dat)
        ## to monitor progress
        if(verbose & i%%10==0) {
            rate <- (Sys.time()-start)/10
            percent <- 100*i/fn
            message(paste("file", i, "-", format(percent,digits=3), "percent completed - rate =", format(rate,digits=4)))
            start <- Sys.time()
        }
    }	## end of for loop
    ## finish up
    .close(genofile, verbose=verbose)
    diagnostics <- list(read.file, row.num, samples, sample.match, missg, snp.chk, chk)
    names(diagnostics) <- c("read.file", "row.num", "samples", "sample.match", "missg", "snp.chk", "chk")
    save(diagnostics, file=diagnostics.filename)
    return(diagnostics)
}

