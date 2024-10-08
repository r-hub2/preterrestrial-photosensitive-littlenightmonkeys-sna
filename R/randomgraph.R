######################################################################
#
# randomgraph.R
#
# copyright (c) 2004, Carter T. Butts <buttsc@uci.edu>
# Last Modified 02/28/24
# Licensed under the GNU General Public License version 2 (June, 1991)
# or later.
#
# Part of the R/sna package
#
# This file contains various routines for random graph generation in
# R.
#
# Contents:
#   rewire.ud
#   rewire.ws
#   rgbn
#   rgmn
#   rgnmix
#   rgraph
#   rguman
#   rgws
#
######################################################################


#rewire.ud - Perform a uniform dyadic rewiring of a graph or graph stack
rewire.ud<-function(g,p,return.as.edgelist=FALSE){
  #Pre-process the raw input
  g<-as.sociomatrix.sna(g)
  if(is.list(g))
    return(lapply(g,rewire.ud,p=p))
  #End pre-processing
  #Coerce g to an array
  if(length(dim(g))==2)
    g<-array(g,dim=c(1,NROW(g),NCOL(g)))
  n<-dim(g)[1]
  nv<-dim(g)[2]
  #Perform the rewiring, and return the result
  rewired<-.C("udrewire_R",g=as.double(g),as.double(n),as.double(nv), as.double(p),PACKAGE="sna")
  if(!return.as.edgelist)
    array(rewired$g,dim=c(n,nv,nv))
  else
    as.edgelist.sna(array(rewired$g,dim=c(n,nv,nv)))
}


#rewire.ws - Perform a Watts-Strogatz rewiring of a graph or graph stack
rewire.ws<-function(g,p,return.as.edgelist=FALSE){
  #Pre-process the raw input
  g<-as.sociomatrix.sna(g)
  if(is.list(g))
    return(lapply(g,rewire.ud,p=p))
  #End pre-processing
  #Coerce g to an array
  if(length(dim(g))==2)
    gi<-array(g,dim=c(1,NROW(g),NCOL(g)))
  go<-gi
  n<-dim(gi)[1]
  nv<-dim(gi)[2]
  #Perform the rewiring, and return the result
  rewired<-.C("wsrewire_R",as.double(gi),go=as.double(go),as.double(n), as.double(nv),as.double(p),PACKAGE="sna")
  if(!return.as.edgelist)
    array(rewired$go,dim=c(n,nv,nv))
  else
    as.edgelist.sna(array(rewired$go,dim=c(n,nv,nv)))
}


#rgbn - Draw from a biased net model
rgbn<-function(n, nv, param=list(pi=0, sigma=0, rho=0, d=0.5, delta=0, epsilon=0), burn=nv*nv*5*1e2, thin=nv*nv*5, maxiter=1e7, method=c("mcmc","cftp"), dichotomize.sib.effects=FALSE, return.as.edgelist=FALSE, seed.graph=NULL, max.density=1){
  #Allocate memory for the graphs (and initialize)
  g<-array(0,dim=c(n,nv,nv))
  if(!is.null(seed.graph)){
    seed.graph<-as.sociomatrix.sna(seed.graph)
    if(length(dim(seed.graph))>2)
      g[1,,]<-seed.graph[1,,]
    else
      g[1,,]<-seed.graph
  }
  #Get the parameter vector
  p<-rep(0,4)
  if(!is.null(param$pi))
    p[1]<-param$pi[1]
  if(!is.null(param$sigma))
    p[2]<-param$sigma[1]
  if(!is.null(param$rho))
    p[3]<-param$rho[1]
  if(!is.null(param$delta))
    p[4]<-param$delta[1]
  if((p[4]>0)&&(match.arg(method)=="cftp"))
    stop("Satiation parameter (delta) not supported with CFTP at present; use MCMC instead.\n")
  if(!is.null(param$d)){           #Base event rates (convert to nv x nv form)
    d<-matrix(param$d,nv,nv)
  }else
    d<-matrix(0,nv,nv)
  if(!is.null(param$epsilon)){     #Inhibition events (in aggregate) - convert to nv x nv form
    if(any(param$epsilon>0)&&(match.arg(method)=="cftp")){
      stop("Inhibition events (epsilon) not supported with CFTP at present; use MCMC instead.\n")
    }
    e<-matrix(param$epsilon,nv,nv)
  }else{                        #Not using, by default
    e<-matrix(0,nv,nv)
  }
  #Take the draws
  early.termination<-FALSE           #Flag for early termination
  if(match.arg(method)=="mcmc"){
    sim<-.C("bn_mcmc_R",g=as.integer(g),as.double(nv),as.double(n), as.double(burn),as.integer(thin),as.double(p[1]),as.double(p[2]),as.double(p[3]),as.double(d), as.double(p[4]),as.double(e),as.integer(dichotomize.sib.effects), dm=as.double(max.density*nv*(nv-1)),PACKAGE="sna")
    g<-array(sim$g,dim=c(n,nv,nv))
    early.termination<-sim$dm<0          #Make sure we didn't stop early
  }else{
    if(any(d>0)){        #If d==0, just return empty graphs
      if(all(d==1)){     #If d==1, just return complete graphs (no delta support yet!)
        for(i in 1:n){
          g[i,,]<-1
          diag(g[i,,])<-0
        }
      }else{             #OK, a nontrivial case.  Let's go for it.
        d[d==0]<-1e-10     #CFTP algorithm not so happy with 0s
        d[d==1]<-1-1e-10   #Doesn't like exact 1s, either
        for(i in 1:n){
          g[i,,]<-matrix(.C("bn_cftp_R",g=as.integer(g[i,,]),as.integer(nv), as.double(p[1]),as.double(p[2]),as.double(p[3]),as.double(d), as.integer(maxiter),as.integer(dichotomize.sib.effects),PACKAGE="sna",NAOK=TRUE)$g,nv,nv)
        }
      }
    }
  }
  #Return the result
  if(return.as.edgelist)
    out<-as.edgelist.sna(g)
  else{
    if(dim(g)[1]==1)
      out<-g[1,,]
    else
      out<-g
  }
  if(early.termination)  #Mark the output as tainted if necessary
    attr(out,"early.termination")<-TRUE
  out
}

#r[i]=1-u^i
#p r[1]^(n-1)
#p^2 (n-1)C1 (1-r[1]) r[2]^(n-2)
#p^3 (n-1)C2 (1-r[1])(1-r[2]) r[3]^(n-3)
#...
#p^i (n-1)C(i-1) r[i]^(n-i) prod_j=1^{i-1} (1-r[j])
# = p^i (n-1)C(i-1) (1-u^i)^(n-i) u^{i(i-1)/2}
#rgmn - Draw a density-conditioned graph
rgnm<-function(n,nv,m,mode="digraph",diag=FALSE,return.as.edgelist=FALSE){
  #Allocate the graph stack and related things
  g<-vector(mode="list",n)
  nv<-rep(nv,length=n)
  m<-rep(m,length=n)
  #Create the graphs
  for(i in 1:n){
    if(nv[i]==0){        #Degenerate null graph
      if(m[i]>0)
        stop("Too many edges requested in rgnm.")
      else{
        mat<-matrix(nrow=0,ncol=3)
        attr(mat,"n")<-0
      }
      g[[i]]<-mat
    }else if(nv[i]==1){  #Isolate (perhaps w/loop)
      if(m[i]>diag)
        stop("Too many edges requested in rgnm.")
      if(m[i]==1){
        mat<-matrix(c(1,1,1),nrow=1,ncol=3)
        attr(mat,"n")<-1
      }else{
        mat<-matrix(nrow=0,ncol=3)
        attr(mat,"n")<-1
      }
      g[[i]]<-mat
    }else if(m[i]==0){   #Empty graph
      mat<-matrix(nrow=0,ncol=3)
      attr(mat,"n")<-nv[i]
      g[[i]]<-mat
    }else{               #Everything else
      if(mode=="digraph"){
        if(diag){          #Digraph w/loops
	  if(m[i]>nv[i]^2)
            stop("Too many edges requested in rgnm.")
          j<-sample(nv[i]^2,m[i])
          r<-((j-1)%%nv[i])+1
          c<-((j-1)%/%nv[i])+1
	  mat<-cbind(r,c,rep(1,m[i]))
	}else{             #Digraph, no loops
	  if(m[i]>nv[i]*(nv[i]-1))
            stop("Too many edges requested in rgnm.")
          j<-sample(nv[i]*(nv[i]-1),m[i])
          c<-((j-1)%/%(nv[i]-1))+1
          r<-(((j-1)%%(nv[i]-1))+1)+((((j-1)%%(nv[i]-1))+1)>(c-1))
	  mat<-cbind(r,c,rep(1,m[i]))
	}
      }else if(mode=="graph"){
        if(diag){          #Unirected graph, w/loops
	  if(m[i]>nv[i]*(nv[i]+1)/2)
            stop("Too many edges requested in rgnm.")
          j<-sample(nv[i]*(nv[i]+1)/2,m[i])
          c<-nv[i]-floor(sqrt(1/4+2*(nv[i]*(nv[i]+1)/2-j))-1/2)
          r<-j+nv[i]-c*(nv[i]+1)+c*(c+1)/2
	  mat<-cbind(r,c,rep(1,m[i]))
	  mat<-rbind(mat,cbind(c,r,rep(1,m[i])))
	}else{             #Undirected graph, no loops
	  if(m[i]>nv[i]*(nv[i]-1)/2)
            stop("Too many edges requested in rgnm.")
          j<-sample(nv[i]*(nv[i]-1)/2,m[i])
          c<-nv[i]-1-floor(sqrt(1/4+2*(choose(nv[i],2)-j))-1/2)
          r<-j-(c-1)*nv[i]+c*(c-1)/2+c
	  mat<-cbind(r,c,rep(1,m[i]))
	  mat<-rbind(mat,cbind(c,r,rep(1,m[i])))
	}
      }else
        stop("Unsupported mode in rgnm.")
      attr(mat,"n")<-nv[i]   #Set graph size
      g[[i]]<-mat
    }
  }
  #Return the results
  if(!return.as.edgelist)
    as.sociomatrix.sna(g)
  else{
    if(n>1)
      g
    else
      g[[1]]
  }
}


#Simple function to produce graphs with fixed exact or expected mixing
#matrices.  n should be the number of desired graphs, tv a vector of types,
#and mix a mixing matrix whose rows and columns correspond to the entries of
#tv.  If method==probability, mix[i,j] should contain the probability of
#an edge from a vertex of type i to one of type j; otherwise, mix[i,j] should
#contain the number of ties from vertices of type i to those of type j in
#the resulting graph.
rgnmix<-function (n, tv, mix, mode="digraph", diag=FALSE, method=c("probability", "exact"), return.as.edgelist=FALSE) 
{
  if(match.arg(method)=="probability"){ #If method==probability, call rgraph
    return(rgraph(n=length(tv),m=n,tprob=mix[tv,tv],mode=mode,diag=diag,return.as.edgelist=return.as.edgelist))
  }else{  #Otherwise, use the exact method
    g<-array(0,dim=c(n,length(tv),length(tv)))
    if(is.character(tv)){
      if(is.null(rownames(mix)))
        stop("Vertex types may only be given as characters for mixing matrices with applicable rownames.\n")
      tv<-match(tv,rownames(mix))
    }
    tcounts<-tabulate(tv,NROW(mix))
    if(mode=="graph"){
      for(i in 1:n){
        for(j in 1:NROW(mix))                   #Row types
          if(tcounts[j]>0){                     #  (ignore if none of type j)
            for(k in j:NROW(mix))               #Col types
              if(tcounts[k]>0){                 #  (ignore if none of type k)
                if(j==k){                       #Diagonal case
                  if(tcounts[j]==1){            #  Single entry
                    if(diag)
                      g[i,tv==j,tv==k]<-mix[j,k] 
                  }else if((tcounts[j]==2)&&(!diag)){      #  Stupid hack for rgnm bug
                    if(mix[j,k])
                      g[i,tv==j,tv==k]<-rbind(c(0,1),c(1,0))
                  }else{                        #  Multiple entries
                    g[i,tv==j,tv==k]<-rgnm(n=1,nv=tcounts[j],m=mix[j,k], mode="graph",diag=diag)
                  }
                }else{                          #Off-diagonal case
                  g[i,tv==j,tv==k][sample(1:(tcounts[j]*tcounts[k]),mix[j,k], replace=FALSE)]<-1
                }
              }
          }
        g[i,,]<-g[i,,]|t(g[i,,])                #Symmetrize
      }
    }else{
      for(i in 1:n){
        for(j in 1:NROW(mix))                   #Row types
          if(tcounts[j]>0){                     #  (ignore if none of type j)
            for(k in 1:NROW(mix))               #Col types
              if(tcounts[k]>0){                 #  (ignore if none of type k)
                if(j==k){                       #Diagonal case
                  if(tcounts[j]==1){            #  Single entry
                    if(diag)
                      g[i,tv==j,tv==k]<-mix[j,k] 
                  }else{                        #  Multiple entries
                     g[i,tv==j,tv==k]<-rgnm(n=1,nv=tcounts[j],m=mix[j,k], mode="digraph",diag=diag)
                  }
                }else{                          #Off-diagonal case
                  g[i,tv==j,tv==k][sample(1:(tcounts[j]*tcounts[k]),mix[j,k], replace=FALSE)]<-1
                }
              }
          }
      }
    }
  }
  #Return the result
  if (n==1) 
    g<-g[1,,]
  if(return.as.edgelist)
    as.edgelist.sna(g)
  else
    g
}


#rgraph - Draw a Bernoulli graph.
rgraph<-function(n,m=1,tprob=0.5,mode="digraph",diag=FALSE,replace=FALSE,tielist=NULL,return.as.edgelist=FALSE){
  if(is.null(tielist)){        #Draw using true Bernoulli methods
    g<-list()
    directed<-(mode=="digraph")
    if(length(dim(tprob))>3)
      stop("tprob must be a single element, vector, matrix, or 3-d array.")
    if(length(dim(tprob))==3){
      pmode<-3
      if((dim(tprob)[1]!=m)||(dim(tprob)[2]!=n)||(dim(tprob)[3]!=n))
        stop("Incorrect tprob dimensions.")
    }else if(length(dim(tprob))==2){
      pmode<-3
      if((dim(tprob)[1]!=n)||(dim(tprob)[2]!=n))
        stop("Incorrect tprob dimensions.")
    }else{
      pmode<-0
      tprob<-rep(tprob,length=m)
    }
    for(i in 1:m){
      if(length(dim(tprob))==3)
        g[[i]]<-.Call("rgbern_R",n,tprob[i,,],directed,diag,pmode,PACKAGE="sna")
      else if(length(dim(tprob))==2)
        g[[i]]<-.Call("rgbern_R",n,tprob,directed,diag,pmode,PACKAGE="sna")
      else
        g[[i]]<-.Call("rgbern_R",n,tprob[i],directed,diag,pmode,PACKAGE="sna")
    }
    #Return the result
    if(return.as.edgelist){
      if(m==1)
        g[[1]]
      else
        g
    }else
      as.sociomatrix.sna(g)
  }else{                       #Draw using edge value resampling
    g<-array(dim=c(m,n,n))
    if(length(dim(tielist))==3){
      for(i in 1:m)
        g[i,,]<-array(sample(as.vector(tielist[i,,]),n*n,replace=replace), dim=c(n,n))
    }else{
      for(i in 1:m)
        g[i,,]<-array(sample(as.vector(tielist),n*n,replace=replace),dim=c(n,n))
    }
    if(!diag)
       for(i in 1:m)
          diag(g[i,,])<-0
    if(mode!="digraph")
       for(i in 1:m){
          temp<-g[i,,]
          temp[upper.tri(temp)]<-t(temp)[upper.tri(temp)]
          g[i,,]<-temp
       }
    #Return the result
    if(!return.as.edgelist){
      if(m==1)
        g[1,,]
      else
        g
    }else
      as.edgelist.sna(g)
  }
}


#rguman - Draw from the U|MAN graph distribution
rguman<-function(n,nv,mut=0.25,asym=0.5,null=0.25,method=c("probability","exact"),return.as.edgelist=FALSE){
  #Create the output structure
  g<-array(0,dim=c(n,nv,nv))
  #Create the dyad list
  dl<-matrix(1:(nv^2),nv,nv)
  dlu<-dl[upper.tri(dl)]
  dll<-t(dl)[upper.tri(dl)]
  ndl<-length(dlu)      #Number of dyads
  #Perform a reality check
  if((match.arg(method)=="exact")&&(mut+asym+null!=ndl))
    stop("Sum of dyad counts must equal number of dyads for method==exact.\n")
  else if((match.arg(method)=="probability")&&(mut+asym+null!=1)){
      s<-mut+asym+null
      mut<-mut/s; asym<-asym/s; null<-null/s
    }    
  #Draw the graphs
  for(i in 1:n){
    #Determine the number of dyads in each class
    if(match.arg(method)=="probability"){
      mc<-rbinom(1,ndl,mut)
      ac<-rbinom(1,ndl-mc,asym/(asym+null))
      nc<-ndl-mc-ac
    }else{
      mc<-mut
      ac<-asym
      nc<-null
    }
    #Draw the dyad states 
    ds<-sample(rep(1:3,times=c(mc,ac,nc)))
    #Place edges accordingly
    if(mc>0){
      g[i,,][dlu[ds==1]]<-1                      #Mutuals
      g[i,,][dll[ds==1]]<-1
    }
    if(ac>0){
      g[i,,][dlu[ds==2]]<-rbinom(ac,1,0.5)       #Asymetrics
      g[i,,][dll[ds==2]]<-1-g[i,,][dlu[ds==2]]
    }
  }
  #Return the result
  if(return.as.edgelist)
    as.edgelist.sna(g)
  else{
    if(n>1)
      g
    else
      g[1,,]
  }
}


#rgws - Draw a graph from the Watts-Strogatz model
rgws<-function(n,nv,d,z,p,return.as.edgelist=FALSE){
  #Begin by creating the lattice
  tnv<-nv^d
  temp<-vector()
  nums<-1:nv
  count<-tnv/nv
  for(i in 1:d){
    temp<-cbind(temp,rep(nums,count))
    nums<-rep(nums,each=nv)
    count<-count/nv
  }
  lat<-as.matrix(dist(temp,method="manhattan"))<=z  #Identify nearest neighbors
  diag(lat)<-0
  #Create n copies of the lattice
  if(n>1)
    lat<-apply(lat,c(1,2),rep,n)
  else
    lat<-array(lat,dim=c(1,tnv,tnv))
  #Rewire the copies
  g<-lat
  lat<-array(.C("wsrewire_R",as.double(lat),g=as.double(g),as.double(n), as.double(tnv),as.double(p),PACKAGE="sna")$g,dim=c(n,tnv,tnv))
  #Return the result
  if(return.as.edgelist)
    as.edgelist.sna(lat)
  else{
    if(n>1)
      lat
    else
      lat[1,,]
  }
}

