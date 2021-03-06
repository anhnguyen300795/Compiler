structure Liveness: sig
	      datatype igraph =
		       IGRAPH of {graph: Graph.graph,
				  tnode: Temp.temp -> Graph.node,
				  gtemp: Graph.node -> Temp.temp,
				  moves: (Graph.node * Graph.node) list}

	      val interferenceGraph: Flow.flowgraph -> igraph * (Graph.node -> Temp.temp list)
	      val show: 'a * igraph -> unit
	  end =
struct

structure G = Graph
type liveSet = (*unit Temp.Table.table * *) Temp.temp list
type liveMap = liveSet G.Table.table
structure M = MakeGraph

datatype igraph =
	 IGRAPH of {graph: Graph.graph,
		    tnode: Temp.temp -> Graph.node,
		    gtemp: Graph.node -> Temp.temp,
		    moves: (Graph.node * Graph.node) list}

structure H = HashTable
val tempNodeMap : (Temp.temp, G.node) H.hash_table = 
    H.mkTable(HashString.hashString o Int.toString, op = ) (42, Fail "not found")

val nodeTempMap = ref (G.Table.empty : Temp.temp G.Table.table)

val flowNodeTempMap = ref (G.Table.empty: (Temp.temp list) G.Table.table)

fun getGlobalTempsFromFlowNode node =
    case G.Table.look (!flowNodeTempMap, node) of
	SOME x => x
      | NONE => []

exception labelNotFoundException;
fun getIgraphNode (temp: Temp.temp): G.node =
    case H.find tempNodeMap temp of
	SOME x => x
      | NONE => raise labelNotFoundException

fun getTempFromIGraphNode (node: G.node): Temp.temp =
    case G.Table.look (!nodeTempMap, node) of
	SOME x => x
      | NONE => raise labelNotFoundException
    

fun getTemps (table, node: G.node): Temp.temp list =
    case G.Table.look(table, node) of
	SOME x => x
      | NONE => []

fun getTempsFromFlowNode (def, use, flowNode): Temp.temp list =
    getTemps(def, flowNode) @ getTemps(use, flowNode)

fun unique (xs: Temp.temp list, notAddable): Temp.temp list =
    let
	fun f (cur, (notAddable, result)) =
	    case Temp.Table.look(notAddable, cur) of
		SOME _ => (notAddable, result)
	      | NONE => (Temp.Table.enter(notAddable, cur, ()), cur::result)
	val (_, temps) = foldl f (notAddable, []) xs 		    
    in
	temps
    end

fun computeLiveMap {control: G.graph, def, use, ismove}: liveMap =
    let
	val flowNodes = G.nodes control
	val shouldContinue = false
		
	fun computeInTemp (outTemps, defTemps, useTemps): Temp.temp list =
	    let
		val notAddable = foldl (fn (cur, acc) => Temp.Table.enter(acc, cur, ())) Temp.Table.empty defTemps
	    in
		unique(unique(outTemps, notAddable)@ useTemps, Temp.Table.empty)
	    end
		
	fun compute (node: G.node, inMap: liveMap, outMap: liveMap) =
	    let
		val oldTempOut = getTemps(outMap, node)
		val oldTempIn = getTemps(inMap, node)
		val successors = G.succ node
		val defs = getTemps(def, node)
		val uses = getTemps(use, node)
				      
		val inUniqTempOut= foldl (fn (succ, acc) => acc @ getTemps(inMap, succ)) [] successors
		(*val _ = print "block temp in----------------------\n"
		val _ = print ("Label: "^ M.getLabel(node) ^"\n")
		val _ = print ("successor: "^ Int.toString(List.length(successors)) ^ "\n")
		val _ = map (fn x => print ((F.makestring F.tempMap x) ^ " - ")) inUniqTempOut
		val _ = print "\n\n"  *)
					 
		val newTempOut = unique(inUniqTempOut, Temp.Table.empty)
		val newTempIn = computeInTemp (newTempOut, defs, uses)
		val hasChanges = (List.length(oldTempOut) <> List.length(newTempOut))
				 orelse (List.length(newTempIn) <> List.length(oldTempIn))
	    in
		(G.Table.enter(inMap, node, newTempIn),
		 G.Table.enter(outMap, node, newTempOut),
		 hasChanges)
	    end
		
	fun f (cur, (inMap, outMap, continue)) =
	    let
		val (newInMap, newOutMap, hasChanges) = compute(cur, inMap, outMap)
	    in
		(newInMap, newOutMap, continue orelse hasChanges)
	    end
		
	fun loop (_, outMap, false): liveMap = outMap
	  | loop (inMap, outMap, true) = loop(foldr f (inMap, outMap, false) flowNodes)
    in
	loop(G.Table.empty, G.Table.empty, true)
    end
	
fun extractAllTemps (def, use, nodes: G.node list): Temp.temp list =
    let
	fun extract (node, acc) =
	    let
		val temps = getTempsFromFlowNode(def, use, node)
		val _ = flowNodeTempMap := G.Table.enter(!flowNodeTempMap, node, temps)
	    in
		temps @ acc
	    end
		
	val allTemps = foldl extract [] nodes
    in
	unique(allTemps, Temp.Table.empty)
    end

fun addNodeToIGraph (graph: G.graph, temps: Temp.temp list): unit list =
    let
	fun addNode temp =
	    let
		val newNode = G.newNode(graph)
		val _ = H.insert tempNodeMap (temp, newNode);
		val _ = nodeTempMap := G.Table.enter (!nodeTempMap, newNode, temp);
	    in	
		()
	    end
    in
	map addNode temps
    end

fun makeEdge cur next = G.mk_edge{from=cur, to=next}
	
fun addEdgeToIGraphAndComputeMoveList (
    flowNodes: G.node list,
    def: liveMap,
    use: liveMap,
    ismove: bool G.Table.table,
    liveTable: liveMap): (G.node * G.node) list =
    let
	fun addEdge (defTemp, outs) =
	    let
		val curNode = getIgraphNode (defTemp)
		(* Prevent node to make edge to itself, or make edge to single case a = c *)
		val addEdge = fn nextNode =>
				 let
				    (* val _ = print ("from "^ Temp.makestring(getTempFromIGraphNode(curNode))^" ")
				     val _ = print ("to "^ Temp.makestring(getTempFromIGraphNode(nextNode))^ " \n") *)
				 in
				     if G.eq(curNode, nextNode)
					     then ()
					     else makeEdge curNode nextNode
				 end
				     
		val _ = map (addEdge o getIgraphNode) outs;
	    in
		()
	    end
		
	fun f (node, acc) =
	    (let
		val defTemps = getTemps(def, node)
		val useTemps = getTemps(use, node)
		val isMove = G.Table.look(ismove, node)
		val liveTemps = getTemps(liveTable, node)
		val _ = (case (defTemps, useTemps, liveTemps) of
			     (* there is max of 1 def temp per flow node *)
			     ([defTemp], _, outs) => addEdge(defTemp, outs)
			   | (_, _, _) => ())
	    in
		case (isMove, defTemps, useTemps) of
		    (SOME (true), [dstTemp], [srcTemp]) => (getIgraphNode(dstTemp), getIgraphNode(srcTemp))::acc
		  | (_, _, _) => acc
	    end)
    in
	foldr f [] flowNodes
    end

fun computeIgraph (
    liveTable: liveMap,
    flowNodes: G.node list,
    def: liveMap,
    use: liveMap,
    temps: Temp.temp list,
    ismove: bool G.Table.table)  =
    let
	val igraph = G.newGraph()
	val _ = addNodeToIGraph (igraph, temps);
	val moveList = addEdgeToIGraphAndComputeMoveList(flowNodes, def, use, ismove, liveTable);
    in
	IGRAPH {
	    graph = igraph,
	    tnode = getIgraphNode,
	    gtemp = getTempFromIGraphNode,
	    moves = moveList
	}
    end
	

fun interferenceGraph (Flow.FGRAPH(e as {control, def, use, ismove})) =
    let
	val flowNodes = G.nodes control
	val temps = extractAllTemps(def, use, flowNodes)
	val liveTable = computeLiveMap(e)
	val igraph = computeIgraph(liveTable, flowNodes, def, use, temps, ismove)
    in
	(igraph, getGlobalTempsFromFlowNode)
    end

fun show (stream, (IGRAPH{graph, tnode, gtemp, moves})) =
    let
	val nodes = G.nodes graph
	val getTempStr = (F.makestring F.tempMap) o gtemp
	fun printNode node =
	    let
		val master = (getTempStr node) ^ ": "
		val adjs = G.adj node
		val next = foldr (fn (cur, acc) => getTempStr(cur) ^ " " ^ acc) "\n" adjs
	    in
		print (master ^ next)
	    end
	val _ = map printNode nodes

    in
	()
    end
end
    
			
