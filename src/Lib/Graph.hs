-- This code is from the fork of 'algebraic-graphs':
-- https://github.com/adithyaov/alga/blob/bbdf26e62825ab9ef27636ac4cffa712bdbcfb7b/src/Algebra/Graph/Labelled/AdjacencyMap/Algorithm.hs
module Lib.Graph
  ( dijkstra,
    shortestPath,
    bellmanFord,
    floydWarshall,
  )
where

import Algebra.Graph.Label
import Algebra.Graph.Labelled.AdjacencyMap
import Data.Map.Strict (Map, (!))
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Relude hiding (one)

-- TODO: Improve documentation for 'dijkstra'.

-- | A generic Dijkstra algorithm that relaxes the list of edges
-- based on the 'Dioid'.
--
-- The heap (min vs max) for Dijkstra is decided based on '<+>'
--
-- We assume two things,
--
-- 1. The underlying semiring is selective i.e. the
-- operation '<+>' always selects one of its arguments.
--
-- 2. The underlying semiring has an optimisation criterion.
--
-- Assuming the above, the Heap type is chosen depending on '<+>':
-- If '<+>' acts like a 'min' then we use a Min Heap else we use a
-- Max Heap.
--
-- The algorithm is best suited to work with the 'Optimum' data type.
--
-- If the edge type is 'Distance' 'Int':
-- @
-- '<+>'  == 'min'
-- '<.>'  == '+'
-- 'one'  == 0
-- 'zero' == 'distance' 'infinity'
-- @
-- @
-- dijkstra ('vertex' 'a') 'a' == 'Map.fromList' [('a', 'one')]
-- dijkstra ('vertex' 'a') 'z' == 'Map.fromList' [('a', 'zero')]
-- dijkstra ('edge' x 'a' 'b') 'a' == 'Map.fromList' [('a', 'one'), ('b', x)]
-- dijkstra ('edge' x 'a' 'b') 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- dijkstra ('vertices' ['a', 'b']) 'a' == 'Map.fromList' [('a', 'one'), ('b', 'zero')]
-- dijkstra ('vertices' ['a', 'b']) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- dijkstra ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'a' == 'Map.fromList' [('a', 'one'), ('b', 3), ('c', 4)]
-- dijkstra ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero'), ('c', 'zero')]
-- @
--
-- If the edge type is 'Capacity' 'Int':
-- @
-- '<+>'  == 'max'
-- '<.>'  == 'min'
-- 'one'  == 'distance' 'infinity'
-- 'zero' == 0
-- @
-- @
-- dijkstra ('vertex' 'a') 'a' == 'Map.fromList' [('a', 'one')]
-- dijkstra ('vertex' 'a') 'z' == 'Map.fromList' [('a', 'zero')]
-- dijkstra ('edge' x 'a' 'b') 'a' == 'Map.fromList' [('a', 'one'), ('b', x)]
-- dijkstra ('edge' x 'a' 'b') 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- dijkstra ('vertices' ['a', 'b']) 'a' == 'Map.fromList' [('a', 'one'), ('b', 'zero')]
-- dijkstra ('vertices' ['a', 'b']) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- dijkstra ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'a' == 'Map.fromList' [('a', 'one'), ('b', 3), ('c', 5)]
-- dijkstra ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero'), ('c', 'zero')]
-- @
dijkstra :: forall a e. (Ord a, Ord e, Dioid e) => AdjacencyMap e a -> a -> Map a e
dijkstra = dijkstra' zero one
  where
    dijkstra' :: (Ord a, Ord e, Dioid e) => e -> e -> AdjacencyMap e a -> a -> Map a e
    dijkstra' z o wam src = maybe zm ((\(_, m, _) -> m) . processG) jsm
      where
        am = adjacencyMap wam
        zm = Map.map (const zero) am :: Map a e
        im = Map.insert src one zm :: Map a e -- queue (reverse lookup)
        is = Set.singleton (one, src) :: Set (e, a) -- queue
        vs = Set.singleton src :: Set a -- visited
        jsm = (is, im, vs) <$ Map.lookup src zm
        view
          | o <+> z == o =
              if o < z
                then Set.minView
                else Set.maxView
          | o <+> z == z =
              if o < z
                then Set.maxView
                else Set.minView
          | otherwise = Set.minView
        processG sm@(s, _, _) = processS (view s) sm
        processS Nothing sm = sm
        processS (Just ((_, v1), s)) (_, m, v) = processG $ relaxV v1 (s, m, v)
        relaxV v1 sm =
          let eL = map (\(v2, e) -> (e, v1, v2)) . Map.toList $ am ! v1
           in foldl' relaxE sm eL
        relaxE (s, m, visit) (e, v1, v2) =
          let n = ((m ! v1) <.> e) <+> (m ! v2)
           in if v2 `Set.member` visit
                then (s, m, visit)
                else (Set.insert (n, v2) s, Map.insert v2 n m, Set.insert v2 visit)

-- Returns shortest distance and path (e, [a]) for all reachable nodes
shortestPath :: forall a e. (Ord a, Ord e, Dioid e) => AdjacencyMap e a -> a -> Map a (e, [a])
shortestPath = dijkstra' zero one
  where
    dijkstra' :: (Ord a, Ord e, Dioid e) => e -> e -> AdjacencyMap e a -> a -> Map a (e, [a])
    dijkstra' z o wam src = maybe zm' ((\(_, m, _, ps) -> genPath m ps) . processG) jsm
      where
        am = adjacencyMap wam
        zm = Map.map (const zero) am :: Map a e
        zm' = Map.map (const zero) am :: Map a (e, [a])
        im = Map.insert src one zm :: Map a e -- queue (reverse lookup)
        is = Set.singleton (one, src) :: Set (e, a) -- queue
        vs = Set.singleton src :: Set a -- visited
        ps = mempty :: Map a a -- parents
        jsm = (is, im, vs, ps) <$ Map.lookup src zm
        view
          | o <+> z == o =
              if o < z
                then Set.minView
                else Set.maxView
          | o <+> z == z =
              if o < z
                then Set.maxView
                else Set.minView
          | otherwise = Set.minView
        processG sm@(s, _, _, _) = processS (view s) sm
        processS Nothing sm = sm
        processS (Just ((_, v1), s)) (_, m, v, ps) = processG $ relaxV v1 (s, m, v, ps)
        relaxV v1 sm =
          let eL = map (\(v2, e) -> (e, v1, v2)) . Map.toList $ am ! v1
           in foldl' relaxE sm eL
        relaxE (s, m, visit, ps) (e, v1, v2) =
          let n = ((m ! v1) <.> e) <+> (m ! v2)
              ps' = if maybe True (> n) (Map.lookup v2 m) then Map.insert v2 v1 ps else ps
           in if v2 `Set.member` visit
                then (s, m, visit, ps)
                else (Set.insert (n, v2) s, Map.insert v2 n m, Set.insert v2 visit, ps')
        genPath :: Map a e -> Map a a -> Map a (e, [a])
        genPath m ps = Map.mapWithKey mapFn m
          where
            mapFn v e = (e, reverse $ unfoldr unfoldFn (Just v)) -- 'reverse' isn't good for performance..
            unfoldFn Nothing = Nothing
            unfoldFn (Just v) =
              if src == v
                then Just (v, Nothing)
                else Just (v, Map.lookup v ps)

-- TODO: Improve documentation for bellmanFord
-- TODO: Improve performance
-- TODO: safely change 'vL' to 'tail vL' in processL

-- | A generic Bellman-Ford algorithm that relaxes the list of edges
-- based on the 'Dioid'.
--
-- We assume two things,
--
-- 1. The underlying semiring is selective i.e. the
-- operation '<+>' always selects one of its arguments.
--
-- 2. The underlying semiring has an optimisation criterion.
--
-- The algorithm is best suited to work with the 'Optimum' data type.
--
-- If the edge type is 'Distance' 'Int':
-- @
-- '<+>'  == 'min'
-- '<.>'  == '+'
-- 'one'  == 0
-- 'zero' == 'distance' 'infinity'
-- @
-- @
-- bellmanFord ('vertex' 'a') 'a' == 'Map.fromList' [('a', 'one')]
-- bellmanFord ('vertex' 'a') 'z' == 'Map.fromList' [('a', 'zero')]
-- bellmanFord ('edge' x 'a' 'b') 'a' == 'Map.fromList' [('a', 'one'), ('b', x)]
-- bellmanFord ('edge' x 'a' 'b') 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- bellmanFord ('vertices' ['a', 'b']) 'a' == 'Map.fromList' [('a', 'one'), ('b', 'zero')]
-- bellmanFord ('vertices' ['a', 'b']) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- bellmanFord ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'a' == 'Map.fromList' [('a', 'one'), ('b', 3), ('c', 4)]
-- bellmanFord ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero'), ('c', 'zero')]
-- @
--
-- If the edge type is 'Capacity' 'Int':
-- @
-- '<+>'  == 'max'
-- '<.>'  == 'min'
-- 'one'  == 'distance' 'infinity'
-- 'zero' == 0
-- @
-- @
-- bellmanFord ('vertex' 'a') 'a' == 'Map.fromList' [('a', 'one')]
-- bellmanFord ('vertex' 'a') 'z' == 'Map.fromList' [('a', 'zero')]
-- bellmanFord ('edge' x 'a' 'b') 'a' == 'Map.fromList' [('a', 'one'), ('b', x)]
-- bellmanFord ('edge' x 'a' 'b') 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- bellmanFord ('vertices' ['a', 'b']) 'a' == 'Map.fromList' [('a', 'one'), ('b', 'zero')]
-- bellmanFord ('vertices' ['a', 'b']) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero')]
-- bellmanFord ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'a' == 'Map.fromList' [('a', 'one'), ('b', 3), ('c', 5)]
-- bellmanFord ('edges' [(5, 'a', 'c'), (3, 'a', 'b'), (1, 'b', 'c')]) 'z' == 'Map.fromList' [('a', 'zero'), ('b', 'zero'), ('c', 'zero')]
-- @
bellmanFord :: (Ord a, Dioid e) => AdjacencyMap e a -> a -> Map a e
bellmanFord wam src = maybe zm processL jim
  where
    am = adjacencyMap wam
    zm = Map.map (const zero) am
    vL = Map.keys am
    jim = Map.insert src one zm <$ Map.lookup src zm
    processL m = foldr (const processR) m vL
    processR m = foldr relaxV m vL
    relaxV v1 m =
      let eL = map (\(v2, e) -> (e, v1, v2)) . Map.toList $ am ! v1
       in foldr relaxE m eL
    relaxE (e, v1, v2) m =
      let n = ((m ! v1) <.> e) <+> (m ! v2)
       in Map.adjust (const n) v2 m

-- TODO: this algorithm is broken; fix it
-- TODO: Improve documentation for floydWarshall
-- TODO: Improve performance
-- TODO: Use a strict fold
-- A generic Floyd-Warshall algorithm that finds all pair optimum path
-- based on the 'Dioid'.
--
-- We assume two things,
--
-- 1. The underlying semiring is selective i.e. the
-- operation '<+>' always selects one of its arguments.
--
-- 2. The underlying semiring has an optimisation criterion.
--
-- The algorithm is best suited to work with the 'Optimum' data type.
--
-- The algorithm returns a 2 dimentional 'Map' with the signature
-- 'Map' a ('Map' a e). Assuming @g :: 'AdjacencyMap' ('Distance' 'Int') 'Int'),
-- if @floydWarshall g == m@ then @m '!' x '!' y@ is the distance between @x@ and @y@.
-- @
-- forall vertex v in g. floydWarshall g ! v == 'dijkstra' g v
-- forall vertex v in g. floydWarshall g ! v == 'bellmanFord' g v
-- @
floydWarshall :: (Ord a, Dioid e) => AdjacencyMap e a -> Map a (Map a e)
floydWarshall wam = relax0 im
  where
    am = adjacencyMap wam
    zm = Map.map (const $ Map.map (const zero) am) am
    em = Map.unionWith Map.union am zm
    im = Map.mapWithKey (Map.adjust (const one)) em
    vL = Map.keys am
    relax0 m = foldr relax1 m vL
    relax1 i m = foldr (relax2 i) m vL
    relax2 i j m = foldr (relax3 i j) m vL
    relax3 i j k m =
      let n = (m ! i ! j) <+> ((m ! i ! k) <.> (m ! k ! j))
       in Map.adjust (Map.adjust (const n) j) i m
