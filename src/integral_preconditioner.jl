
#######################################################################################
#                                                                                     #
#                     Preconditioners for the Integral System                         #
#                                                                                     #
#######################################################################################

type IntegralPreconditioner
    n::Int64  # number of grid points in the x direction
    nSubs::Int64
    subDomains
    nIt::Int64
    P # permutation matrix
    precondtype # preconditioner type Jacobi, GaussSeidel Opt
    function IntegralPreconditioner(subDomains; nIt = 1, precondtype ="GS")
        n = subDomains[1].n
        nSubs = length(subDomains)
        P = generatePermutationMatrix(n,nSubs);
        new(n,nSubs, subDomains,nIt, P, precondtype) # don't know if it's the best answer
    end
end

function \(M::IntegralPreconditioner, b::Array{Complex128,1})
    #println("Applying the polarized Traces Preconditioner")
    if M.precondtype == "GS"
        return PrecondGaussSeidel(M.subDomains, M.P*b, M.nIt)
    elseif M.precondtype == "Jac"
        return PrecondJacobi(M.subDomains, M.P*b, M.nIt)
    end
end

function PrecondJacobi(subArray, v::Array{Complex128,1}, nit)
    # function to apply the block Jacobi preconditioner using the data
    # TODO add dimension checks
    u = 0*v;
    for ii = 1:nit
        # splitting the vector in two parts
        udown = u[1:round(Integer,end/2)];
        uup   = u[(1+round(Integer,end/2)):end];
        # f - Ru^{n-1}
        if norm(u)!=0
            # skip this step in the first iteration
            udownaux = v[1:round(Integer,end/2)]       - applyU(subArray, uup);
            uupaux   = v[(1+round(Integer,end/2)):end] - applyL(subArray, udown);
        else
            udownaux = v[1:round(Integer,end/2)]
            uupaux   = v[(1+round(Integer,end/2)):end]
        end

        vdown = applyDinvDown(subArray,udownaux);
        vup   = applyDinvUp(subArray,uupaux);
        u    = vcat(vdown, vup );
    end
    return u;
end

function PrecondGaussSeidel(subArray, v::Array{Complex128,1}, nit; verbose=false)
    # function to apply the block Gauss-Seidel Preconditioner
    # input :   subArray  array pointer to the set of subdomains
    #           v         rhs to be solved
    #           nit       number of iterations
    # output:   u         Approximated solution
    # using a first guess equals to zero

    println("Applying the preconditioner");
    u = 0*v;
    for ii = 1:nit

        # splitting the vector in two parts
        udown = u[1:round(Integer,end/2)];
        uup   = u[(1+round(Integer,end/2)):end];

        # f - Ru^{n-1}
        if norm(u)  != 0
            udownaux = v[1:round(Integer,end/2)]       - applyU(subArray, uup);
        else
            udownaux = v[1:round(Integer,end/2)]
        end
        uupaux   = v[(1+round(Integer,end/2)):end] ;

        # applying the inverses
        vdown = applyDinvDown(subArray,udownaux);
        vup   = applyDinvUp(subArray, uupaux - applyL(subArray,vdown));

        if verbose
            println("magnitude of the update = ", norm(u[:] -  vcat(vdown, vup ))/norm(v[:]));
        end

        # concatenatinc the solution
        u    = vcat(vdown, vup );

    end
    return u;
end
