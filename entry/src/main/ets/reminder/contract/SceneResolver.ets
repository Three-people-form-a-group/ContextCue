export enum SceneResolveStatus {
  RESOLVED = 'RESOLVED',
  AMBIGUOUS = 'AMBIGUOUS',
  NOT_FOUND = 'NOT_FOUND'
}

export interface SceneCandidate {
  id: string;
  name: string;
}

export interface SceneResolveResult {
  status: SceneResolveStatus;
  match?: SceneCandidate;
  candidates: SceneCandidate[];
}

export interface SceneResolver {
  resolveByName(sceneName: string): Promise<SceneResolveResult>;
}
