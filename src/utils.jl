
function excess_uncertainty(l::Float64,
                            u::Float64,
                            root_l::Float64,
                            root_u::Float64,
                            depth::Int64,
                            eta::Float64,
                            discount::Float64)

  eu::Float64 = (u-l) - #width of current node
                (eta * (root_u-root_l)) * # epsilon
                (discount^(-depth))
  return eu
end

# Returns the observation with the highest weighted excess uncertainty
# ("WEU"), along with the value of the WEU.
# root: Root of the search tree, passed to facilitate computation of the
# excess uncertainty

function get_best_weuo{S,A,O,L,U}(qnode::QNode{S,A,O,L,U},
                       root::VNode{S,A,O,L,U},
                       config::DESPOTConfig,
                       discount::Float64)
  weighted_eu_star::Float64 = -Inf
  oStar = collect(keys(qnode.obs_to_node))[1] # init with something
  
  for (obs,node) in qnode.obs_to_node
        weighted_eu = node.weight / qnode.weight_sum *
                            excess_uncertainty(node.lbound,
                                               node.ubound,
                                               root.lbound,
                                               root.ubound,
                                               qnode.depth+1,
                                               config.eta,
                                               discount)

        if weighted_eu > weighted_eu_star
            weighted_eu_star = weighted_eu
            oStar = obs
        end
  end
  return oStar, weighted_eu_star
end

# Get WEUO for a single observation branch
function get_node_weuo{S,A,O,L,U}(qnode::QNode{S,A,O,L,U}, root::VNode{S,A,O,L,U}, obs::Int64)
   weighted_eu = qnode.obs_to_node[obs].weight / qnode.weight_sum *
                        excess_uncertainty(
                        qnode.obs_to_node[obs].lbound, qnode.obs_to_node[obs].ubound,
                        root.lbound, root.ubound, qnode.depth+1)
   return weighted_eu
end

#
# Returns the v-node corresponding to a given observation
function belief{S,A,O,L,U}(qnode::QNode{S,A,O,L,U}, obs::O)
  return qnode.obs_to_node[obs]
end

function validate_bounds(lb::Float64, ub::Float64, config::DESPOTConfig)
  if (ub >= lb)
    return
  end

  if (ub > lb - config.tiny) || config.approximate_ubound
    ub = lb
  else
    println("lower bound - $lb, upper bound - $ub")
    @assert(false)
  end
end

function almost_the_same(x::Float64, y::Float64, config::DESPOTConfig)
  return abs(x-y) < config.tiny
end

# TODO: This probably can be replaced by just a weighted sampling call - check later
function sample_particles!{S}(sampled_particles::Vector{DESPOTParticle{S}},
                           pool::Vector{DESPOTParticle{S}}, #TODO: see if this can be tightened
                           N::Int64,
                           seed::UInt32,
                           rand_max::Int64)

    # Ensure particle weights sum to exactly 1
    sum_without_last =  0;
    
    for i in 1:length(pool)-1
        sum_without_last += pool[i].weight
    end
    
    end_weight = 1 - sum_without_last

    # Divide the cumulative frequency into N equally-spaced parts
    num_sampled = 0
    
    if OS_NAME == :Linux
        cseed = Cuint[seed]
        r = ccall((:rand_r, "libc"), Int, (Ptr{Cuint},), cseed)/rand_max/N
    else #Windows, etc
        srand(seed)
        r = Base.rand()/N
    end

    curr_particle = 0
    cum_sum = 0

    for i=1:N
        while cum_sum < r
            curr_particle += 1
            if curr_particle == length(pool)
                cum_sum += end_weight
            else
                cum_sum += pool[curr_particle].weight
            end
        end

        sampled_particles[i] = DESPOTParticle(pool[curr_particle].state, i-1, 1.0/N) #index particles starting with 0
        r += 1.0/N
    end
    return sampled_particles
end
