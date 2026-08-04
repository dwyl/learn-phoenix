export default class ElementRef {
    static onUnlock(el: any, callback: any): any;
    constructor(el: any);
    el: any;
    loadingRef: number;
    lockRef: number;
    maybeUndo(ref: any, phxEvent: any, eachCloneCallback: any): void;
    isWithin(ref: any): boolean;
    undoLocks(ref: any, phxEvent: any, eachCloneCallback: any): void;
    undoLoading(ref: any, phxEvent: any): void;
    isLoadingUndoneBy(ref: any): boolean;
    isLockUndoneBy(ref: any): boolean;
    isFullyResolvedBy(ref: any): boolean;
    canUndoLoading(ref: any): boolean;
}
