declare module 'astro:content' {
	export interface RenderResult {
		Content: import('astro/runtime/server/index.js').AstroComponentFactory;
		headings: import('astro').MarkdownHeading[];
		remarkPluginFrontmatter: Record<string, any>;
	}
	interface Render {
		'.md': Promise<RenderResult>;
	}

	export interface RenderedContent {
		html: string;
		metadata?: {
			imagePaths: Array<string>;
			[key: string]: unknown;
		};
	}
}

declare module 'astro:content' {
	type Flatten<T> = T extends { [K: string]: infer U } ? U : never;

	export type CollectionKey = keyof AnyEntryMap;
	export type CollectionEntry<C extends CollectionKey> = Flatten<AnyEntryMap[C]>;

	export type ContentCollectionKey = keyof ContentEntryMap;
	export type DataCollectionKey = keyof DataEntryMap;

	type AllValuesOf<T> = T extends any ? T[keyof T] : never;
	type ValidContentEntrySlug<C extends keyof ContentEntryMap> = AllValuesOf<
		ContentEntryMap[C]
	>['slug'];

	export type ReferenceDataEntry<
		C extends CollectionKey,
		E extends keyof DataEntryMap[C] = string,
	> = {
		collection: C;
		id: E;
	};
	export type ReferenceContentEntry<
		C extends keyof ContentEntryMap,
		E extends ValidContentEntrySlug<C> | (string & {}) = string,
	> = {
		collection: C;
		slug: E;
	};
	export type ReferenceLiveEntry<C extends keyof LiveContentConfig['collections']> = {
		collection: C;
		id: string;
	};

	/** @deprecated Use `getEntry` instead. */
	export function getEntryBySlug<
		C extends keyof ContentEntryMap,
		E extends ValidContentEntrySlug<C> | (string & {}),
	>(
		collection: C,
		// Note that this has to accept a regular string too, for SSR
		entrySlug: E,
	): E extends ValidContentEntrySlug<C>
		? Promise<CollectionEntry<C>>
		: Promise<CollectionEntry<C> | undefined>;

	/** @deprecated Use `getEntry` instead. */
	export function getDataEntryById<C extends keyof DataEntryMap, E extends keyof DataEntryMap[C]>(
		collection: C,
		entryId: E,
	): Promise<CollectionEntry<C>>;

	export function getCollection<C extends keyof AnyEntryMap, E extends CollectionEntry<C>>(
		collection: C,
		filter?: (entry: CollectionEntry<C>) => entry is E,
	): Promise<E[]>;
	export function getCollection<C extends keyof AnyEntryMap>(
		collection: C,
		filter?: (entry: CollectionEntry<C>) => unknown,
	): Promise<CollectionEntry<C>[]>;

	export function getLiveCollection<C extends keyof LiveContentConfig['collections']>(
		collection: C,
		filter?: LiveLoaderCollectionFilterType<C>,
	): Promise<
		import('astro').LiveDataCollectionResult<LiveLoaderDataType<C>, LiveLoaderErrorType<C>>
	>;

	export function getEntry<
		C extends keyof ContentEntryMap,
		E extends ValidContentEntrySlug<C> | (string & {}),
	>(
		entry: ReferenceContentEntry<C, E>,
	): E extends ValidContentEntrySlug<C>
		? Promise<CollectionEntry<C>>
		: Promise<CollectionEntry<C> | undefined>;
	export function getEntry<
		C extends keyof DataEntryMap,
		E extends keyof DataEntryMap[C] | (string & {}),
	>(
		entry: ReferenceDataEntry<C, E>,
	): E extends keyof DataEntryMap[C]
		? Promise<DataEntryMap[C][E]>
		: Promise<CollectionEntry<C> | undefined>;
	export function getEntry<
		C extends keyof ContentEntryMap,
		E extends ValidContentEntrySlug<C> | (string & {}),
	>(
		collection: C,
		slug: E,
	): E extends ValidContentEntrySlug<C>
		? Promise<CollectionEntry<C>>
		: Promise<CollectionEntry<C> | undefined>;
	export function getEntry<
		C extends keyof DataEntryMap,
		E extends keyof DataEntryMap[C] | (string & {}),
	>(
		collection: C,
		id: E,
	): E extends keyof DataEntryMap[C]
		? string extends keyof DataEntryMap[C]
			? Promise<DataEntryMap[C][E]> | undefined
			: Promise<DataEntryMap[C][E]>
		: Promise<CollectionEntry<C> | undefined>;
	export function getLiveEntry<C extends keyof LiveContentConfig['collections']>(
		collection: C,
		filter: string | LiveLoaderEntryFilterType<C>,
	): Promise<import('astro').LiveDataEntryResult<LiveLoaderDataType<C>, LiveLoaderErrorType<C>>>;

	/** Resolve an array of entry references from the same collection */
	export function getEntries<C extends keyof ContentEntryMap>(
		entries: ReferenceContentEntry<C, ValidContentEntrySlug<C>>[],
	): Promise<CollectionEntry<C>[]>;
	export function getEntries<C extends keyof DataEntryMap>(
		entries: ReferenceDataEntry<C, keyof DataEntryMap[C]>[],
	): Promise<CollectionEntry<C>[]>;

	export function render<C extends keyof AnyEntryMap>(
		entry: AnyEntryMap[C][string],
	): Promise<RenderResult>;

	export function reference<C extends keyof AnyEntryMap>(
		collection: C,
	): import('astro/zod').ZodEffects<
		import('astro/zod').ZodString,
		C extends keyof ContentEntryMap
			? ReferenceContentEntry<C, ValidContentEntrySlug<C>>
			: ReferenceDataEntry<C, keyof DataEntryMap[C]>
	>;
	// Allow generic `string` to avoid excessive type errors in the config
	// if `dev` is not running to update as you edit.
	// Invalid collection names will be caught at build time.
	export function reference<C extends string>(
		collection: C,
	): import('astro/zod').ZodEffects<import('astro/zod').ZodString, never>;

	type ReturnTypeOrOriginal<T> = T extends (...args: any[]) => infer R ? R : T;
	type InferEntrySchema<C extends keyof AnyEntryMap> = import('astro/zod').infer<
		ReturnTypeOrOriginal<Required<ContentConfig['collections'][C]>['schema']>
	>;

	type ContentEntryMap = {
		
	};

	type DataEntryMap = {
		"band-i": Record<string, {
  id: string;
  body?: string;
  collection: "band-i";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band-ii": Record<string, {
  id: string;
  body?: string;
  collection: "band-ii";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band-iii": Record<string, {
  id: string;
  body?: string;
  collection: "band-iii";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band1-anhang": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band1-anhang";
  data: InferEntrySchema<"band1-anhang">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band1-inhaltsverzeichnis": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band1-inhaltsverzeichnis";
  data: InferEntrySchema<"band1-inhaltsverzeichnis">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band1-titelblatt": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band1-titelblatt";
  data: InferEntrySchema<"band1-titelblatt">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band2-anhang": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band2-anhang";
  data: InferEntrySchema<"band2-anhang">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band2-inhaltsverzeichnis": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band2-inhaltsverzeichnis";
  data: InferEntrySchema<"band2-inhaltsverzeichnis">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band2-titelblatt": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band2-titelblatt";
  data: InferEntrySchema<"band2-titelblatt">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band3-anhang": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band3-anhang";
  data: InferEntrySchema<"band3-anhang">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band3-inhaltsverzeichnis": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band3-inhaltsverzeichnis";
  data: InferEntrySchema<"band3-inhaltsverzeichnis">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"band3-titelblatt": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "band3-titelblatt";
  data: InferEntrySchema<"band3-titelblatt">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"gesamtwerk": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "gesamtwerk";
  data: InferEntrySchema<"gesamtwerk">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "kapitel";
  data: InferEntrySchema<"kapitel">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-01": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "kapitel-01";
  data: InferEntrySchema<"kapitel-01">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-02": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "kapitel-02";
  data: InferEntrySchema<"kapitel-02">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-03": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-03";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-04": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-04";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-05": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-05";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-06": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-06";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-07": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-07";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-08": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-08";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-09": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-09";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-10": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-10";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-11": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-11";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-12": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-12";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-13": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-13";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-14": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-14";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-15": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-15";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-16": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-16";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-17": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-17";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-18": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-18";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-19": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-19";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-20": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-20";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-21": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-21";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-22": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-22";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-23": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-23";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-28": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-28";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-29": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-29";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-30": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-30";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"kapitel-32": Record<string, {
  id: string;
  body?: string;
  collection: "kapitel-32";
  data: any;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"quellenverzeichnis": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "quellenverzeichnis";
  data: InferEntrySchema<"quellenverzeichnis">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"schlussdialog": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "schlussdialog";
  data: InferEntrySchema<"schlussdialog">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"titelblatt": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "titelblatt";
  data: InferEntrySchema<"titelblatt">;
  rendered?: RenderedContent;
  filePath?: string;
}>;
"vorwort": Record<string, {
  id: string;
  render(): Render[".md"];
  slug: string;
  body: string;
  collection: "vorwort";
  data: InferEntrySchema<"vorwort">;
  rendered?: RenderedContent;
  filePath?: string;
}>;

	};

	type AnyEntryMap = ContentEntryMap & DataEntryMap;

	type ExtractLoaderTypes<T> = T extends import('astro/loaders').LiveLoader<
		infer TData,
		infer TEntryFilter,
		infer TCollectionFilter,
		infer TError
	>
		? { data: TData; entryFilter: TEntryFilter; collectionFilter: TCollectionFilter; error: TError }
		: { data: never; entryFilter: never; collectionFilter: never; error: never };
	type ExtractDataType<T> = ExtractLoaderTypes<T>['data'];
	type ExtractEntryFilterType<T> = ExtractLoaderTypes<T>['entryFilter'];
	type ExtractCollectionFilterType<T> = ExtractLoaderTypes<T>['collectionFilter'];
	type ExtractErrorType<T> = ExtractLoaderTypes<T>['error'];

	type LiveLoaderDataType<C extends keyof LiveContentConfig['collections']> =
		LiveContentConfig['collections'][C]['schema'] extends undefined
			? ExtractDataType<LiveContentConfig['collections'][C]['loader']>
			: import('astro/zod').infer<
					Exclude<LiveContentConfig['collections'][C]['schema'], undefined>
				>;
	type LiveLoaderEntryFilterType<C extends keyof LiveContentConfig['collections']> =
		ExtractEntryFilterType<LiveContentConfig['collections'][C]['loader']>;
	type LiveLoaderCollectionFilterType<C extends keyof LiveContentConfig['collections']> =
		ExtractCollectionFilterType<LiveContentConfig['collections'][C]['loader']>;
	type LiveLoaderErrorType<C extends keyof LiveContentConfig['collections']> = ExtractErrorType<
		LiveContentConfig['collections'][C]['loader']
	>;

	export type ContentConfig = typeof import("./../src/content.config.js");
	export type LiveContentConfig = never;
}
