import Graph from "graphology"
import Sigma from "sigma"

function cssValue(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim()
}

function currentPalette() {
  const status = (name) => cssValue(`--graph-status-${name}`)
  const relation = (name) => cssValue(`--graph-relation-${name}`)

  return {
    label: cssValue("--graph-label"),
    root: cssValue("--graph-root"),
    status: {
      triage: status("triage"),
      in_progress: status("in_progress"),
      waiting: status("waiting"),
      resolved: status("resolved"),
      verified: status("verified"),
      closed: status("closed"),
      default: status("default"),
    },
    relation: {
      reopened_from: relation("reopened_from"),
      duplicate_of: relation("duplicate_of"),
      blocks: relation("blocks"),
      blocked_by: relation("blocked_by"),
      related: relation("related"),
      default: relation("default"),
    },
  }
}

export default {
  mounted() {
    this.themeObserver = new MutationObserver(() => this.refreshTheme())
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    })

    this.colorScheme = window.matchMedia("(prefers-color-scheme: dark)")
    this.handleColorScheme = () => this.refreshTheme()
    this.colorScheme.addEventListener("change", this.handleColorScheme)

    this.renderGraph()
  },

  updated() {
    this.destroyGraph()
    this.renderGraph()
  },

  destroyed() {
    this.destroyGraph()
    this.themeObserver?.disconnect()
    this.colorScheme?.removeEventListener("change", this.handleColorScheme)
  },

  refreshTheme() {
    this.destroyGraph()
    this.renderGraph()
  },

  renderGraph() {
    const data = JSON.parse(this.el.dataset.graph || "{}")
    if (!data.nodes || data.nodes.length === 0) return

    const palette = currentPalette()
    const graph = new Graph()

    for (const node of data.nodes) {
      graph.addNode(node.id, {
        label: node.label,
        x: node.x,
        y: node.y,
        size: node.size,
        color: node.root
          ? palette.root
          : palette.status[node.status] || palette.status.default,
        url: node.url,
      })
    }

    for (const edge of data.edges) {
      if (!graph.hasNode(edge.source) || !graph.hasNode(edge.target)) continue
      graph.addEdgeWithKey(edge.id, edge.source, edge.target, {
        label: edge.label,
        color: palette.relation[edge.relation] || palette.relation.default,
        size: 1,
      })
    }

    this.renderer = new Sigma(graph, this.el, {
      defaultEdgeType: "arrow",
      // 密なグラフではエッジ名を出さず、色と凡例で関係を示す
      renderEdgeLabels: data.edges.length <= 8,
      labelDensity: 0.55,
      labelGridCellSize: 36,
      labelRenderedSizeThreshold: 8,
      labelSize: 13,
      edgeLabelSize: 11,
      stagePadding: 120,
      labelColor: {color: palette.label},
      edgeLabelColor: {color: palette.label},
    })

    this.renderer.on("clickNode", ({node}) => {
      const url = graph.getNodeAttribute(node, "url")
      if (url) window.location.assign(url)
    })
  },

  destroyGraph() {
    if (this.renderer) {
      this.renderer.kill()
      this.renderer = null
    }
  },
}
