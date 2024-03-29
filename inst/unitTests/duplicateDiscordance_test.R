test_duplicateDiscordance <- function() {
  # snp annotation
  snpID <- 1:10
  chrom <- rep(1L, 10)
  pos <- 101:110
  snpdf <- data.frame(snpID=snpID, chromosome=chrom, position=pos)
  snpAnnot <- SnpAnnotationDataFrame(snpdf)
  
  # scan annotation
  scanID <- 1:6
  subjID <- c("a","b","c","b","b","a")
  scandf <- data.frame(scanID=scanID, subjID=subjID)
  scanAnnot <- ScanAnnotationDataFrame(scandf)
  
  # netCDF
  geno <- matrix(c(c(0,0,0,0,0,1,1,1,1,1),
                   c(1,1,1,1,1,2,2,2,2,2),
                   c(0,0,0,0,0,0,0,0,0,0),
                   c(1,0,1,1,1,2,2,2,2,0),
                   c(1,1,0,1,0,2,2,2,2,0),
                   c(0,0,0,0,2,2,1,1,NA,1)), ncol=6)
  mgr <- MatrixGenotypeReader(genotype=geno, snpID=snpID,
    chromosome=chrom, position=pos, scanID=scanID)
  genoData <- GenotypeData(mgr, snpAnnot=snpAnnot, scanAnnot=scanAnnot)

  # expected values
  a.exp <- c(0,0,0,0,1,1,0,0,0,0)
  b.exp <- c(0,2,2,0,2,0,0,0,0,2)
  subj.disc.exp <- c(0,1,1,0,2,1,0,0,0,1)
  tot.disc.exp <- c(0,2,2,0,3,1,0,0,0,2)
  npair.exp <- c(4,4,4,4,4,4,4,4,3,4)
  b.subj.exp <- matrix(c(0.0,0.2,0.3,0.2,0.0,0.3,0.3,0.3,0.0), ncol=3,
                       dimnames=list(c(2,4,5),c(2,4,5)))
  b.corr.exp <- matrix(c(1, cor(geno[,2], geno[,4]), cor(geno[,2], geno[,5]),
                         cor(geno[,4], geno[,2]), 1, cor(geno[,4], geno[,5]),
                         cor(geno[,5], geno[,2]), cor(geno[,5], geno[,4]), 1),
                       ncol=3, dimnames=list(c(2,4,5),c(2,4,5)))
  snpcor.exp <- c(cor(c(0,1),c(0,1)),
                  NA, #cor(c(0,1),c(0,0)),
                  cor(c(0,1),c(0,1)),
                  cor(c(0,1),c(0,1)),
                  cor(c(0,1),c(2,1)),
                  NA, #cor(c(1,2),c(2,2)),
                  cor(c(1,2),c(1,2)),
                  cor(c(1,2),c(1,2)),
                  NA, #cor(c(1,2),c(NA,2)),
                  cor(c(1,2),c(1,0)))
  
  disc <- duplicateDiscordance(genoData, "subjID", corr.by.snp=TRUE,
                               one.pair.per.subj=FALSE)
  checkIdentical(disc[[1]]$n.disc.subj, subj.disc.exp)
  checkIdentical(disc[[1]]$discordant, tot.disc.exp)
  checkIdentical(disc[[1]]$npair, npair.exp)
  checkIdentical(disc[[1]]$correlation, snpcor.exp)
  checkEquals(disc[[2]]$b, b.subj.exp)
  checkEquals(disc[[3]]$b, b.corr.exp)

  
  # check only one scan per subject
  disc <- duplicateDiscordance(genoData, "subjID", corr.by.snp=TRUE,
                               one.pair.per.subj=TRUE)
  checkIdentical(disc[[1]]$discordant, disc[[1]]$n.disc.subj)
  checkEquals(2, max(disc[[1]]$npair))

  
  # check minor allele discordance
  snp.exclude <- 2
  afreq <- c(3/12, 2/12, 2/12, 3/12, 4/12, 9/12, 8/12, 8/12, 7/10, 4/12)
  # minor    A,A,A,A,A,B,B,B,B,A
  # major    0,0,0,0,0,2,2,2,2,0
  a.npr <- c(0,0,0,0,1,1,1,1,0,1)[-2]
  a.exp <- c(0,0,0,0,1,1,0,0,0,0)[-2]
  b.npr <- c(3,3,3,3,3,0,0,0,0,2)[-2]
  b.exp <- c(0,2,2,0,2,0,0,0,0,2)[-2]
  subj.disc.exp <- as.numeric((a.exp > 0) + (b.exp > 0))
  tot.disc.exp <- a.exp + b.exp
  npair.exp <- a.npr + b.npr
  snpcor.exp <- c(NA, #cor(c(NA,1),c(NA,1)),
#                  cor(c(NA,1),c(NA,0)),
                  NA, #cor(c(NA,1),c(NA,1)),
                  NA, #cor(c(NA,1),c(NA,1)),
                  cor(c(0,1),c(2,1)),
                  NA, #cor(c(1,2),c(2,2)),
                  NA, #cor(c(1,NA),c(1,NA)),
                  NA, #cor(c(1,NA),c(1,NA)),
                  NA, #cor(c(1,NA),c(NA,NA)),
                  cor(c(1,2),c(1,0)))
  disc <- duplicateDiscordance(genoData, "subjID", corr.by.snp=TRUE,
                               minor.allele.only=TRUE, allele.freq=afreq,
                               snp.exclude=snp.exclude,
                               one.pair.per.subj=FALSE)
  checkIdentical(disc[[1]]$n.disc.subj, subj.disc.exp)
  checkIdentical(disc[[1]]$discordant, tot.disc.exp)
  checkIdentical(disc[[1]]$npair, npair.exp)
  checkIdentical(disc[[1]]$correlation, snpcor.exp)
  
  
  # exclude some scans
  scan.exclude <- 5
  a.exp <- c(0,0,0,0,1,1,0,0,0,0)
  b.exp <- c(0,1,0,0,0,0,0,0,0,1)
  subj.disc.exp <- c(0,1,0,0,1,1,0,0,0,1)
  tot.disc.exp <- c(0,1,0,0,1,1,0,0,0,1)
  npair.exp <- c(2,2,2,2,2,2,2,2,1,2)
  b.subj.exp <- matrix(c(0.0,0.2,0.2,0.0), ncol=2,
                       dimnames=list(c(2,4),c(2,4)))
  
  disc <- duplicateDiscordance(genoData, "subjID", scan.exclude=scan.exclude,
                               one.pair.per.subj=FALSE)
  checkIdentical(disc[[1]]$n.disc.subj, subj.disc.exp)
  checkIdentical(disc[[1]]$discordant, tot.disc.exp)
  checkIdentical(disc[[1]]$npair, npair.exp)
  checkEquals(disc[[2]]$b, b.subj.exp)

  
  # exclude some snps
  snp.exclude <- c(2,10)
  a.exp <- c(0,0,0,1,1,0,0,0)
  b.exp <- c(0,2,0,2,0,0,0,0)
  subj.disc.exp <- c(0,1,0,2,1,0,0,0)
  tot.disc.exp <- c(0,2,0,3,1,0,0,0)
  npair.exp <- c(4,4,4,4,4,4,4,3)
  
  disc <- duplicateDiscordance(genoData, "subjID", snp.exclude=snp.exclude,
                               one.pair.per.subj=FALSE)
  checkIdentical(disc[[1]]$n.disc.subj, subj.disc.exp)
  checkIdentical(disc[[1]]$discordant, tot.disc.exp)
  checkIdentical(disc[[1]]$npair, npair.exp)

  
  # check that Y chrom SNPs for females are ignored
  snpAnnot$chromosome <- c(rep(1L, 2), rep(25L, 8))
  scanAnnot$sex <- "F"
  mgr <- MatrixGenotypeReader(genotype=geno, snpID=snpID,
    chromosome=snpAnnot$chromosome, position=pos, scanID=scanID)
  genoData <- GenotypeData(mgr, snpAnnot=snpAnnot, scanAnnot=scanAnnot)

  snp.exclude <- 10
  a.exp <- c(0,0,0,0,0,0,0,0,0)
  b.exp <- c(0,2,0,0,0,0,0,0,0)
  subj.disc.exp <- c(0,1,0,0,0,0,0,0,0)
  tot.disc.exp <- c(0,2,0,0,0,0,0,0,0)
  npair.exp <- c(4,4,0,0,0,0,0,0,0)
  
  disc <- duplicateDiscordance(genoData, "subjID", snp.exclude=snp.exclude,
                               one.pair.per.subj=FALSE)
  checkIdentical(disc[[1]]$n.disc.subj, subj.disc.exp)
  checkIdentical(disc[[1]]$discordant, tot.disc.exp)
  checkIdentical(disc[[1]]$npair, npair.exp)
}
