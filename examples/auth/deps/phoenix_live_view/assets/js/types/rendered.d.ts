export function modifyRoot(html: any, attrs: any, clearInnerHTML: any): any[];
export default class Rendered {
    static extract(diff: any): {
        diff: any;
        title: any;
        reply: any;
        events: any;
    };
    constructor(viewId: any, rendered: any);
    viewId: any;
    rendered: {};
    magicId: number;
    parentViewId(): any;
    toString(onlyCids: any): {
        buffer: string;
        streams: Set<any>;
    };
    recursiveToString(rendered: any, components: any, onlyCids: any, changeTracking: any, rootAttrs: any): {
        buffer: string;
        streams: Set<any>;
    };
    componentCIDs(diff: any): number[];
    isComponentOnlyDiff(diff: any): boolean;
    getComponent(diff: any, cid: any): any;
    resetRender(cid: any): void;
    mergeDiff(diff: any): void;
    cachedFindComponent(cid: any, cdiff: any, oldc: any, newc: any, cache: any): any;
    mutableMerge(target: any, source: any): any;
    doMutableMerge(target: any, source: any): void;
    clone(diff: any): any;
    mergeKeyed(target: any, source: any): void;
    cloneMerge(target: any, source: any, pruneMagicId: any): any;
    componentToString(cid: any): {
        buffer: any;
        streams: Set<any>;
    };
    pruneCIDs(cids: any): void;
    get(): {};
    isNewFingerprint(diff?: {}): boolean;
    templateStatic(part: any, templates: any): any;
    nextMagicID(): string;
    toOutputBuffer(rendered: any, templates: any, output: any, changeTracking: any, rootAttrs?: {}): void;
    comprehensionToBuffer(rendered: any, templates: any, output: any, changeTracking: any): void;
    dynamicToBuffer(rendered: any, templates: any, output: any, changeTracking: any): void;
    recursiveCIDToString(components: any, cid: any, onlyCids: any): {
        buffer: string;
        streams: Set<any>;
    };
}
