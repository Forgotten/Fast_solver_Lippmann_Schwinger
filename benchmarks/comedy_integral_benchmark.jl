# small script to test how to perform the domain decomposition
# we try to compute fast solution without tampering with A directly,
# in this file we add the possibility to use Sparse MKL for the matrix
# vector multiplication


# Clean version of the DDM ode

using PyPlot
using Devectorize
using IterativeSolvers
using Pardiso

include("../src/FastConvolution.jl")
include("../src/quadratures.jl")
include("../src/subdomains.jl")
include("../src/preconditioner.jl")
include("../src/integral_preconditioner.jl")

#Defining Omega
# H = [ 0.005, 0.0025, 0.00125, 0.000625]
# Subs = [ 4,8,16,32]

# NPML = [ 10, 12, 14, 16]

H = [ 0.005, 0.0025]
Subs = [ 4,8]

NPML = [ 10, 12]


maxInnerIter = 2

for ll = 1:length(H)

    h = H[ll]

    nSubdomains = Subs[ll];
    npml = NPML[ll]


    k = (1/h)
    # setting the correct number of threads for FFTW and
    # BLAS, this can be further
    FFTW.set_num_threads(16)
    blas_set_num_threads(16)
    
    println("Frequency is ", k/(2*pi))
    println("Number of discretization points is ", 1/h)
    
    # size of box
    a  = 1
    x = -a/2:h:a/2
    y = -a/2:h:a/2
    n = length(x)
    m = length(y)
    N = n*m
    X = repmat(x, 1, m)[:]
    Y = repmat(y', n,1)[:]
    
    
    println("Number of Subdomains is ", nSubdomains)
    # we solve \triangle u + k^2(1 + nu(x))u = 0
    # in particular we compute the scattering problem
    
    
    # we extract from a "tabulated" dictionary
    # the good modification for the quadrature modification
    (ppw,D) = referenceValsTrapRule();
    D0 = D[1];
    
    contrast = -0.3;
    # pacman profile
    nu1(x,z) = ( contrast*(  (((x-0.5).^2 + (z-0.5).^2).<0.152 ).*
                                        (  ((x-0.5).^2 + (z-0.5).^2).>0.11 )).*
                                        (1-(abs(x-0.5).<0.1).*(z.>0.5))   +
    
                contrast*(  (((x-0.5).^2 + (z-0.5).^2).<0.040 ).*
                                        (  ((x-0.5).^2 + (z-0.5).^2).>0.018 )).*
                                        (1-(abs(x-0.5).<0.08).*(z.<0.5)));
    
    nu(x,y) = nu1(x+0.5,y+0.5); # sign is important the convention with respect to Leslie paper is different
    
    
    Ge = buildGConv(x,y,h,n,m,D0,k);
    GFFT = fft(Ge);
    
    fastconv = FastM(GFFT,nu(X,Y),3*n-2,3*m-2,n, m, k);
    
    println("Building the A sparse")
    @time As = buildSparseA(k,X,Y,D0, n ,m);
    
    println("Building A*G in sparse format")
    @time AG = buildSparseAG(k,X,Y,D0, n ,m);
    
    # need to check everything here :S
    
    Mapproxsp = k^2*(AG*spdiagm(nu(X,Y)));
    Mapproxsp = As + Mapproxsp;
    
    # number of interior points for each subdomain
    SubDomLimits = round(Integer, floor(linspace(1,m+1,nSubdomains+1)))
    # index in y. of the first row of each subdomain
    idx1 = SubDomLimits[1:end-1]
    # index in y of the last row of each subdomains
    idxn = SubDomLimits[2:end]-1
    
    SubArray = [ Subdomain(As,AG,Mapproxsp,x,y, idx1[ii],idxn[ii], npml, h, nu, k, solvertype = "MKLPARDISO") for ii = 1:nSubdomains];
    
    
    # this step is a hack to avoid building new vectors in int32 every time
    for ii = 1:nSubdomains
        convert64_32!(SubArray[ii])
    end
    
    tic();
    for ii=1:nSubdomains
        factorize!(SubArray[ii])
    end
    
    println("Time for the factorization ", toc())
    
    Precond = PolarizedTracesPreconditioner(As, SubArray, nIt =1);
    
    # we build a set of different incident waves
    
    theta = collect(1:0.3:2*pi)
    time = 0
    nit = 0
    for ii = 1:length(theta)
    
        u_inc = exp(k*im*(X*cos(theta[ii]) + Y*sin(theta[ii])));
        rhs = -(fastconv*u_inc - u_inc);
    
        u = zeros(Complex128,N);
        tic();
        info = gmres!(u, fastconv, rhs, Precond)
        time += toc();
        nit+=countnz(info[2].residuals[:])
    end
    
    
    
    println("Solving the comedy central logo wavespeed with the integral preconditioner")
    println("Frequency is ", k/(2*pi))
    println("Number of discretization points is ", 1/h)
    println("Number of Subdomains is ", nSubdomains)
    println("average time ", time/length(theta))
    println("npml points  ", npml )
    println("average number of iterations ", nit/length(theta))
    println("maximum number of inner iterations ", maxInnerIter )
    


end
