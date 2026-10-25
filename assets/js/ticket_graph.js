import Graph from "graphology"
import Sigma from "sigma"

const palettes = {
  light: {
    label: "#0f172a",
    root: "#0f172a",
    status: {
      triage: "#b45309",
      in_progress: "#2563eb",
      waiting: "#b45309",
      resolved: "#0e7490",
      verified: "#15803d",
      closed: "#475569",
      default: "#334155",
    },
    relation: {
      reopened_from: "#dc2626",
      duplicate_of: "#7c3aed",
      blocks: "#2563eb",
      blocked_by: "#2563eb",
      related: "#64748b",
      default: "#64748b",
    },
  },
  dark: {
    label: "#e2e8f0",
    root: "#f8fafc",
    status: {
      triage: "#fbbf24",
      in_progress: "#60a5fa",
      waiting: "#fbbf24",
      resolved: "#22d3ee",
      verified: "#4ade80",
      closed: "#94a3b8",
      default: "#cbd5e1",
    },
    relation: {
      reopened_from: "#f87171",
      duplicate_of: "#c084fc",
      blocks: "#60a5fa",
      blocked_by: "#60a5fa",
      related: "#94a3b8",
      default: "#94a3b8",
    },
  },
}

function currentPalette() {
  const theme = document.documentElement.getAttribute("data-theme")
  const dark =
    theme === "dark" ||
    (!theme && window.matchMedia("(prefers-color-scheme: dark)").matches)

  return dark ? palettes.dark : palettes.light
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
      renderEdgeLabels: true,
      labelDensity: 0.8,
      labelRenderedSizeThreshold: 6,
      stagePadding: 90,
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
