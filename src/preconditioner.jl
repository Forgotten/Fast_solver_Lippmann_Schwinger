# We add the preconditioner (Gauss Seidel type in this file)
# we need to be sure to be having just a pointer

type GSPreconditioner
    n::Int64  # number of grid points in the x direction
    nSubs::Int64
    subDomains
    tol ::Float64
    function GSPreconditioner(subDomains; tol = 1e-4)
        n = subDomains[1].n
        nSubs = length(subDomains)
        new(n,nSubs, subDomains, tol) # don't know if it's the best answer
    end
end

type Preconditioner
    As
    Msp
    GSPreconditioner

    function Preconditioner(As,Msp,subDomains; tol = 1e-4)

        new(As,Msp, GSPreconditioner(subDomains,tol)) # don't know if it's the best answer
    end

end


import Base.\

function \(M::GSPreconditioner, b::Array{Complex128,1})
    println("Applying the polarized Traces Preconditioner")
    return precondGS(M.subDomains, b)
end

function \(M::Preconditioner, b::Array{Complex128,1})
    println("Applying the sparsifying Preconditioner")
    y = zeros(b)
    gmres!(y, M.Msp, M.As*b, M.GSPreconditioner, tol = 1e-4)
    return y
end


function precondGS(subDomains, source::Array{Complex128,1})
    ## We are only implementing the Jacobi version of the preconditioner
    nSubs = length(subDomains);

    n = subDomains[1].n
    # building the local rhs
    rhsLocal = [ zeros(Complex128,subDomains[ii].n*subDomains[ii].m) for ii = 1:nSubs ]

    # copying the wave-fields
    for ii = 1:nSubs
        rhsLocal[ii][subDomains[ii].indVolIntLocal] = source[subDomains[ii].indVolInt]
    end

    uLocalArray = [solve(subDomains[ii],rhsLocal[ii] )  for  ii = 1:nSubs]

    u_0  = zeros(Complex128,n*nSubs)
    u_1  = zeros(Complex128,n*nSubs)
    u_n  = zeros(Complex128,n*nSubs)
    u_np = zeros(Complex128,n*nSubs)

    index = 1:n

    # Downward sweep

    u_n[index]  = uLocalArray[1][subDomains[1].ind_n]
    u_np[index] = uLocalArray[1][subDomains[1].ind_np]

    # populate the traces

    for ii = 1:nSubs
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        if ii != 1
            u_0[(ii-1)*n + index] = -uLocalArray[ii][ind_0]
            u_1[(ii-1)*n + index] = -uLocalArray[ii][ind_1]
        end
        if ii !=nSubs
            u_n[(ii-1)*n  + index] = -uLocalArray[ii][ind_n]
            u_np[(ii-1)*n + index] = -uLocalArray[ii][ind_np]
        end

    end


    u_n[ index] = -u_n[ index]
    u_np[index] = -u_np[index]

    for ii = 2:nSubs-1
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the partitioned source
        rhsLocaltemp = zeros(Complex128,size(rhsLocal[ii])[1]) ;

        rhsLocaltemp[subDomains[ii].ind_0] =  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]
        rhsLocaltemp[subDomains[ii].ind_1] = -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]

        uDown = solve(subDomains[ii],rhsLocaltemp)

        u_n[(ii-1)*n  + index] = -u_n[(ii-1)*n  + index] + uDown[ind_n]
        u_np[(ii-1)*n + index] = -u_np[(ii-1)*n + index] + uDown[ind_np]

    end

    #Applying L

    for ii = 2:nSubs
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the partitioned source
        rhsLocaltemp = zeros(Complex128,size(rhsLocal[ii])[1]) ;

        if ii != nSubs

        rhsLocaltemp[subDomains[ii].ind_0]  =  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]
        rhsLocaltemp[subDomains[ii].ind_1]  = -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]


        rhsLocaltemp[subDomains[ii].ind_n]  = -subDomains[ii].H[ind_n,ind_np]*u_np[(ii-1)*n + index]
        rhsLocaltemp[subDomains[ii].ind_np] =  subDomains[ii].H[ind_np,ind_n]*u_n[(ii-1)*n + index]

        else
            rhsLocaltemp[subDomains[ii].ind_0]  =  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]
            rhsLocaltemp[subDomains[ii].ind_1]  = -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]
        end

        uL = solve(subDomains[ii],rhsLocaltemp)

        # saving the reflections
        u_0[(ii-1)*n + index] -= uL[ind_0]
        u_1[(ii-1)*n + index] -= uL[ind_1] - u_np[(ii-2)*n + index]

    end

    # Upward sweep

     u_0[(nSubs-1)*n + index] = -u_0[(nSubs-1)*n + index]
     u_1[(nSubs-1)*n + index] = -u_1[(nSubs-1)*n + index]

     for ii = nSubs-1:-1:2
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the parititioned source (we may need a sparse source)
        rhsLocaltemp = zeros(Complex128,size(rhsLocal[ii])[1]) ;

        rhsLocaltemp[subDomains[ii].ind_np] =  subDomains[ii].H[ind_np,ind_n]*u_0[(ii)*n + index]
        rhsLocaltemp[subDomains[ii].ind_n]  = -subDomains[ii].H[ind_n,ind_np]*u_1[(ii)*n + index]

        uUp = solve(subDomains[ii],rhsLocaltemp)

        u_0[(ii-1)*n + index] = -u_0[(ii-1)*n + index] + uUp[ind_0]
        u_1[(ii-1)*n + index] = -u_1[(ii-1)*n + index] + uUp[ind_1]

    end

    # reconstruction

    uPrecond = Complex128[]

    for ii = 1:nSubs

        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the parititioned source
        rhsLocaltemp = copy(rhsLocal[ii]);

        # adding the source at the boundaries
        if ii!= 1
            # we need to be carefull at the edges
            rhsLocaltemp[subDomains[ii].ind_1]  += -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]
            rhsLocaltemp[subDomains[ii].ind_0]  +=  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]

        end
        if ii!= nSubs
            rhsLocaltemp[subDomains[ii].ind_np] +=  subDomains[ii].H[ind_np,ind_n]*u_0[(ii)*n + index]
            rhsLocaltemp[subDomains[ii].ind_n]  += -subDomains[ii].H[ind_n,ind_np]*u_1[(ii)*n + index]
        end

        uLocal = solve(subDomains[ii],rhsLocaltemp)

        uPrecond = vcat(uPrecond,uLocal[subDomains[ii].indVolIntLocal])
    end
    return  uPrecond
end

function precondJacobi(subDomains, source::Array{Complex128,1})
    ## We are only implementing the Jacobi version of the preconditioner
    nSubs = length(subDomains);

    n = subDomains[1].n
    # building the local rhs
    rhsLocal = [ zeros(Complex128,subDomains[ii].n*subDomains[ii].m) for ii = 1:nSubs ]

    # copying the wave-fields
    for ii = 1:nSubs
        rhsLocal[ii][subDomains[ii].indVolIntLocal] = source[subDomains[ii].indVolInt]
    end

    uLocalArray = [solve(subDomains[ii],rhsLocal[ii] )  for  ii = 1:nSubs]

    u_0  = zeros(Complex128,n*nSubs)
    u_1  = zeros(Complex128,n*nSubs)
    u_n  = zeros(Complex128,n*nSubs)
    u_np = zeros(Complex128,n*nSubs)

    index = 1:n

    # Downward sweep

    u_n[index]  = uLocalArray[1][subDomains[1].ind_n]
    u_np[index] = uLocalArray[1][subDomains[1].ind_np]

    # populate the traces

    for ii = 1:nSubs
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        if ii != 1
            u_0[(ii-1)*n + index] = -uLocalArray[ii][ind_0]
            u_1[(ii-1)*n + index] = -uLocalArray[ii][ind_1]
        end
        if ii !=nSubs
            u_n[(ii-1)*n  + index] = -uLocalArray[ii][ind_n]
            u_np[(ii-1)*n + index] = -uLocalArray[ii][ind_np]
        end

    end

    u_n[ index] = -u_n[ index]
    u_np[index] = -u_np[index]

    for ii = 2:nSubs-1
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the partitioned source
        rhsLocaltemp = zeros(Complex128,size(rhsLocal[ii])[1]) ;

        rhsLocaltemp[subDomains[ii].ind_0] =  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]
        rhsLocaltemp[subDomains[ii].ind_1] = -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]

        uDown = solve(subDomains[ii],rhsLocaltemp)

        u_n[(ii-1)*n  + index] = -u_n[(ii-1)*n  + index] + uDown[ind_n]
        u_np[(ii-1)*n + index] = -u_np[(ii-1)*n + index] + uDown[ind_np]

    end

    # Upward sweep

     u_0[(nSubs-1)*n + index] = -u_0[(nSubs-1)*n + index]
     u_1[(nSubs-1)*n + index] = -u_1[(nSubs-1)*n + index]

     for ii = nSubs-1:-1:2
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the parititioned source (we may need a sparse source)
        rhsLocaltemp = zeros(Complex128,size(rhsLocal[ii])[1]) ;

        rhsLocaltemp[subDomains[ii].ind_np] =  subDomains[ii].H[ind_np,ind_n]*u_0[(ii)*n + index]
        rhsLocaltemp[subDomains[ii].ind_n]  = -subDomains[ii].H[ind_n,ind_np]*u_1[(ii)*n + index]

        uUp = solve(subDomains[ii],rhsLocaltemp)

        u_0[(ii-1)*n + index] = -u_0[(ii-1)*n + index] + uUp[ind_0]
        u_1[(ii-1)*n + index] = -u_1[(ii-1)*n + index] + uUp[ind_1]

    end

    # reconstruction

    uPrecond = Complex128[]

    for ii = 1:nSubs

        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the parititioned source
        rhsLocaltemp = copy(rhsLocal[ii]);

        # adding the source at the boundaries
        if ii!= 1
            # we need to be carefull at the edges
            rhsLocaltemp[subDomains[ii].ind_1]  += -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]
            rhsLocaltemp[subDomains[ii].ind_0]  +=  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]

        end
        if ii!= nSubs
            rhsLocaltemp[subDomains[ii].ind_np] +=  subDomains[ii].H[ind_np,ind_n]*u_0[(ii)*n + index]
            rhsLocaltemp[subDomains[ii].ind_n]  += -subDomains[ii].H[ind_n,ind_np]*u_1[(ii)*n + index]
        end

        uLocal = solve(subDomains[ii],rhsLocaltemp)

        uPrecond = vcat(uPrecond,uLocal[subDomains[ii].indVolIntLocal])
    end
    return  uPrecond
end


function precondGSOptimized(subDomains, source::Array{Complex128,1})
    ## We are only implementing the Jacobi version of the preconditioner
    nSubs = length(subDomains);

    n = subDomains[1].n
    # building the local rhs
    rhsLocal = [ zeros(Complex128,subDomains[ii].n*subDomains[ii].m) for ii = 1:nSubs ]

    # copying the sources to local field
    for ii = 1:nSubs
        rhsLocal[ii][subDomains[ii].indVolIntLocal] = source[subDomains[ii].indVolInt]
    end

    # uLocalArray = [solve(subDomains[ii],rhsLocal[ii] )  for  ii = 1:nSubs]

    # allocating memory for the traces
    u_0  = zeros(Complex128,n*nSubs)
    u_1  = zeros(Complex128,n*nSubs)
    u_n  = zeros(Complex128,n*nSubs)
    u_np = zeros(Complex128,n*nSubs)

    index = 1:n

    # Downward sweep

    for ii = 1:nSubs
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a local copy of the local rhs
        rhsLocaltemp = copy(rhsLocal[ii]);

        if ii !=1
            rhsLocaltemp[subDomains[ii].ind_0] +=  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]
            rhsLocaltemp[subDomains[ii].ind_1] += -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]
        end

        # solving the rhs
        vDown = solve(subDomains[ii],rhsLocaltemp)

        # extracting the traces
        if ii != nSubs
            u_n[(ii-1)*n  + index] = vDown[ind_n]
            u_np[(ii-1)*n + index] = vDown[ind_np]
        end

    end


    # Upward sweep + reflections

     for ii = nSubs:-1:1
        # this will be slow most likely but it is readable
        # we will need to modify this part
        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the parititioned source
        rhsLocaltemp = copy(rhsLocal[ii]);

        # adding the source at the boundaries
        if ii!= 1
            # we need to be carefull at the edges
            rhsLocaltemp[subDomains[ii].ind_1]  += -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]
            rhsLocaltemp[subDomains[ii].ind_0]  +=  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]

        end
        if ii!= nSubs
            rhsLocaltemp[subDomains[ii].ind_np] +=  subDomains[ii].H[ind_np,ind_n]*u_0[(ii)*n + index]
            rhsLocaltemp[subDomains[ii].ind_n]  += -subDomains[ii].H[ind_n,ind_np]*u_1[(ii)*n + index]
        end

        uUp = solve(subDomains[ii],rhsLocaltemp)

        if ii > 1
            u_0[(ii-1)*n + index] = uUp[ind_0]
            u_1[(ii-1)*n + index] = uUp[ind_1] - u_np[(ii-2)*n + index]
        end
    end

    # reconstruction

    uPrecond = Complex128[]

    for ii = 1:nSubs

        ind_0  = subDomains[ii].ind_0
        ind_1  = subDomains[ii].ind_1
        ind_n  = subDomains[ii].ind_n
        ind_np = subDomains[ii].ind_np

        # making a copy of the parititioned source
        rhsLocaltemp = copy(rhsLocal[ii]);

        # adding the source at the boundaries
        if ii!= 1
            # we need to be carefull at the edges
            rhsLocaltemp[subDomains[ii].ind_1]  += -subDomains[ii].H[ind_1,ind_0]*u_n[(ii-2)*n + index]
            rhsLocaltemp[subDomains[ii].ind_0]  +=  subDomains[ii].H[ind_0,ind_1]*u_np[(ii-2)*n + index]

        end
        if ii!= nSubs
            rhsLocaltemp[subDomains[ii].ind_np] +=  subDomains[ii].H[ind_np,ind_n]*u_0[(ii)*n + index]
            rhsLocaltemp[subDomains[ii].ind_n]  += -subDomains[ii].H[ind_n,ind_np]*u_1[(ii)*n + index]
        end

        uLocal = solve(subDomains[ii],rhsLocaltemp)

        uPrecond = vcat(uPrecond,uLocal[subDomains[ii].indVolIntLocal])
    end
    return  uPrecond
end






