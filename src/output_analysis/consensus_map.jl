using Clustering
using Compose
using DataFrames
using Gadfly
using LinearAlgebra

mutable struct Posterior_similarity_matrix
    psm::Vector
    names::Vector{String}
    Posterior_similarity_matrix(K, n_obs) = new([Matrix(1.0I, n_obs, n_obs) for k in 1:(K + (K > 1))],
                                                Vector{String}(undef, K + (K > 1)))
end


"""
`generate_psm(outputFile::String, burnin::Int64 = 0, thin::Int64 = 1)`

Generates a posterior similarity matrix from pmdi output
## Input
- `outputFile::S    tring` a string referring to the location on disk of pmdi output
- `burnin::Int64` an integer of the number of initial iterations to discard as burn-in
- `thin::Int64` an integer for the rate at which to thin output, `thin = 2` discards
every second iteration

## Output
A struct of class `Posterior_similarity_matrix` containing:
    - `psm` K n × n matrices where element (i, j) measures how frequently observation
    i and j are co-clustered in dataset k. If `K > 1` an overall consensus matrix
    is also included which is an element-wise average of the K other matrices
    - `names` a vector of the dataset names
"""
function generate_psm(outputFile::String, burnin::Int64 = 0, thin::Int64 = 1)
    outputNames = split(readline(outputFile), ',')
    output = readdlm(outputFile, ',', header = false, skipstart = burnin + 1)

    K = sum(occursin.(r"MassParameter", outputNames))

    output = output[1:thin:end, (K + binomial(K, 2) + (K == 1) + 2):end]

    n_obs = size(output, 2) / K
    @assert mod(n_obs, 1) == 0 "Error: Datasets have different number of observations"
    n_obs = Int64(n_obs)
    n_iter = size(output, 1)

    psm = Posterior_similarity_matrix(K, n_obs)
    psm.names[1:K] = unique(map(x -> split(x, '_')[1], outputNames[(K + (K == 1) + binomial(K, 2) + 2):end]))
    if K > 1
        psm.names[K + 1] = "Overall"
    end
    for k = 1:K
        for j = 1:(n_obs - 1)
            for i = (j + 1):n_obs
                psm.psm[k][i, j] = sum(output[:, i + n_obs * (k - 1)] .== output[:, j + n_obs * (k - 1)]) / n_iter
            end
        end
    end
    if K > 1
        for k = 1:K
            psm.psm[K + 1] += psm.psm[k] / K
        end
            psm.psm[K + 1][diagind(psm.psm[K + 1])] .= 1.0
    end

    return psm
end

"""
`consensus_map(psm::Posterior_similarity_matrix, nclust::Int64, orderby::Int64 = 0)`

Generates a consensus map plot for a given posterior similarity matrix
## Input
- `psm` a posterior similarity matrix struct as output from `generate_psm`
- `nclust` the number of clusters to highlight in the data
- `orderby` observations in all plots are ordered in a way to separate clusters as well
as possible. `orderby` specifies which dataset should be used to inform this ordering.
`orderby = 0` will let the overall consensus dictate the ordering.
## Output
- K + 1 (or K if K == 1) consensus maps illustrating the clustering output in each
of K datasets.

**Note: the output of this needs to be saved to file to be viewed. This can be done
as follows:**
`using Gadfly
draw(SVG("path/to/file.svg"), consensus_map(psm, nclust, orderby))`
**This should be fixed pending a bug fix in the Gadfly packge**
"""
function consensus_map(psm::Posterior_similarity_matrix, nclust::Int64, orderby::Int64 = 0)
    if orderby == 0
        orderby = size(psm.psm, 1)
    end
    hc = hclust(1 .- Symmetric(psm.psm[orderby], :L), linkage = :average, uplo = :L)
    cuts = cutree(hc, k = nclust)[hc.order]
    ticks = indexin(1:nclust, cuts) .+ 0.5
    order = sortperm(hc.order)
    K = length(psm.psm)
    subplots = [spy(Symmetric(psm.psm[k], :L)[hc.order, hc.order],
                    Coord.cartesian(raster = true,
                    aspect_ratio = 1.0,
                    xmin = 0.5, ymin = 0.5,
                    xmax = size(psm.psm[1], 1) + 0.5,
                    ymax = size(psm.psm[1], 1) + 0.5,
                    yflip = true),
                    Theme(key_position = :none),
                    Guide.xlabel(psm.names[k]),
                    Guide.ylabel(""),
                    Guide.xticks(ticks = ticks),
                    Guide.yticks(ticks = ticks),
                    Scale.x_continuous(labels = i -> ""),
                    Scale.y_continuous(labels = i -> ""),
                    Scale.color_continuous(colormap=Scale.lab_gradient("#2A186C", "#3B9287", "#FDEF9A"), maxvalue = 1.0))
                for k in 1:K]
    return hstack(subplots)
    """
    outplot = vstack([Compose.compose(context(0, 0, 1 / (K - 1), 1 / (K - 1)), render(subplots[k])) for k in 1:(K - 1)]...)
    outplot = hstack(Compose.compose(context(0, 0, 1.0h, 1), render(subplots[K])),
                    outplot)
    draw(SVG("test.svg", (width)inch, (width)inch), outplot)


    plot_df = DataFrame([String, Int64, Int64, Float64],
                        [:Dataset, :x, :y, :ps],
                        size(psm.psm, 1) * size(psm.psm[1], 1) ^ 2)

    n = 1
    for k in 1:size(psm.names, 1)
        for j in 1:(size(psm.psm[1], 1))
            for i in j:size(psm.psm[1], 1)
                if i == j
                    plot_df[:Dataset][n] = psm.names[k]
                    plot_df[:x][n] = order[i]
                    plot_df[:y][n] = order[j]
                    plot_df[:ps][n] = psm.psm[k][i, j]
                    n += 1
                else
                    plot_df[:Dataset][n:(n+1)] = psm.names[k]
                    plot_df[:x][n] = plot_df[:y][n + 1] = order[i]
                    plot_df[:y][n] = plot_df[:x][n + 1] = order[j]
                    plot_df[:ps][n] = plot_df[:ps][n + 1] = psm.psm[k][i, j]
                    n += 2
                end
            end
        end
    end
    plot(plot_df, x = :x, y = :y, color = :ps, xgroup = :Dataset,
    Geom.subplot_grid(Coord.cartesian(raster = true,
                                      aspect_ratio = 1.0,
                                      xmin = 0.5, ymin = 0.5,
                                      xmax = maximum(plot_df[:x]) + 0.5,
                                      ymax = maximum(plot_df[:y]) + 0.5,
                                      yflip = true),
                       Geom.rectbin,
                       Guide.xticks(ticks = ticks),
                       Guide.yticks(ticks = ticks),
                       Guide.xlabel(""),
                       Scale.x_continuous,
                       Scale.y_continuous))
       """
end
