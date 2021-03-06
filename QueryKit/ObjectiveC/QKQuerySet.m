#import "QKQuerySet.h"

NSString * const QKQuerySetErrorDomain = @"QKQuerySetErrorDomain";

@interface QKQuerySet ()

@property (nonatomic, strong) NSArray *resultsCache;

@end

@implementation QKQuerySet

#pragma mark - Creation

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext entityDescription:(NSEntityDescription *)entityDescription {
  return [self initWithManagedObjectContext:managedObjectContext entityDescription:entityDescription predicate:nil sortDescriptors:nil range:NSMakeRange(NSNotFound, NSNotFound)];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext fetchRequest:(NSFetchRequest *)fetchRequest {
  return [self initWithManagedObjectContext:managedObjectContext entityDescription:fetchRequest.entity predicate:fetchRequest.predicate sortDescriptors:fetchRequest.sortDescriptors range:NSMakeRange(NSNotFound, NSNotFound)];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext entityDescription:(NSEntityDescription *)entityDescription predicate:(NSPredicate *)predicate sortDescriptors:(NSArray *)sortDescriptors range:(NSRange)range {
  if (self = [super init]) {
    _managedObjectContext = managedObjectContext;
    _entityDescription = entityDescription;
    _predicate = [predicate copy];
    _sortDescriptors = sortDescriptors? [sortDescriptors copy] : @[];
    _range = range;
  }

  return self;
}

- (instancetype)init {
  NSString *reason = [NSString stringWithFormat:@"%@ Failed to call designated initializer.", NSStringFromClass([self class])];
  @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

#pragma mark - Equality

- (NSUInteger)hash {
  return [self.managedObjectContext hash];
}

- (BOOL)isEqual:(id)object {
  return (self == object) || ([object isKindOfClass:[QKQuerySet class]] && [self isEqualToQuerySet:object]);
}

- (BOOL)isEqualToQuerySet:(QKQuerySet *)queryset {
  return [self.managedObjectContext isEqual:[queryset managedObjectContext]] && [self.entityDescription isEqual:[queryset entityDescription]] && [self.predicate isEqual:[queryset predicate]] && [self.sortDescriptors isEqual:[queryset sortDescriptors]] && NSEqualRanges(self.range, queryset.range);
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[[self class] allocWithZone:zone] initWithManagedObjectContext:self.managedObjectContext entityDescription:self.entityDescription predicate:self.predicate sortDescriptors:self.sortDescriptors range:self.range];
}

#pragma mark - NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len {
  return [[self array:nil] countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark - Fetching

- (NSFetchRequest *)fetchRequest {
  NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
  [fetchRequest setEntity:_entityDescription];
  [fetchRequest setPredicate:self.predicate];
  [fetchRequest setSortDescriptors:self.sortDescriptors];

  if (self.range.location != NSNotFound) {
    fetchRequest.fetchOffset = self.range.location;
    fetchRequest.fetchLimit = self.range.length;
  }

  return fetchRequest;
}

- (NSUInteger)count:(NSError **)error {
  NSUInteger count = 0;

  if (_resultsCache) {
    count = [_resultsCache count];
  } else {
    NSFetchRequest *fetchRequest = [self fetchRequest];
    count = [self.managedObjectContext countForFetchRequest:fetchRequest error:error];
  }

  return count;
}

- (NSArray *)array:(NSError **)error {
  if (_resultsCache == nil) {
    _resultsCache = [self.managedObjectContext executeFetchRequest:[self fetchRequest] error:error];
  }

  return _resultsCache;
}

- (NSSet *)set:(NSError **)error {
  NSArray *array = [self array:error];
  NSSet *set;

  if (array != nil) {
    set = [NSSet setWithArray:array];
  }

  return set;
}

- (NSOrderedSet *)orderedSet:(NSError **)error {
  NSArray *array = [self array:error];
  NSOrderedSet *orderedSet;

  if (array != nil) {
    orderedSet = [NSOrderedSet orderedSetWithArray:array];
  }

  return orderedSet;
}

- (BOOL)enumerateObjects:(void (^)(NSManagedObject *object, NSUInteger index, BOOL *stop))block error:(NSError **)error {
  NSArray *array = [self array:error];

  if (array != nil) {
    [array enumerateObjectsUsingBlock:block];
  }

  return array != nil;
}

- (BOOL)each:(void (^)(NSManagedObject *managedObject))block error:(NSError **)error {
  return [self enumerateObjects:^(NSManagedObject * _Nonnull object, NSUInteger index, BOOL * _Nonnull stop) {
    block(object);
  } error:error];
}

#pragma mark - Deletion

- (NSUInteger)deleteObjects:(NSError **)error {
  NSArray *array = [self array:error];

  NSUInteger count = 0;

  if (array != nil) {
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;

    for (NSManagedObject *managedObject in array) {
      [managedObjectContext deleteObject:managedObject];
      ++count;
    }
  }

  return count;
}

@end

@implementation QKQuerySet (Sorting)

- (instancetype)orderBy:(NSArray *)sortDescriptors {
  return [[QKQuerySet alloc] initWithManagedObjectContext:_managedObjectContext entityDescription:_entityDescription predicate:_predicate sortDescriptors:sortDescriptors range:self.range];
}

- (instancetype)reverse {
  NSMutableArray *sortDescriptors = [[NSMutableArray alloc] initWithCapacity:[_sortDescriptors count]];

  for (NSSortDescriptor *sortDescriptor in _sortDescriptors) {
    [sortDescriptors addObject:[sortDescriptor reversedSortDescriptor]];
  }

  return [[QKQuerySet alloc] initWithManagedObjectContext:_managedObjectContext entityDescription:_entityDescription predicate:_predicate sortDescriptors:sortDescriptors range:self.range];
}

@end

@implementation QKQuerySet (Filtering)

- (instancetype)exclude:(NSPredicate *)predicate {
  predicate = [[NSCompoundPredicate alloc] initWithType:NSNotPredicateType subpredicates:@[predicate]];

  if (_predicate) {
    predicate = [[NSCompoundPredicate alloc] initWithType:NSAndPredicateType subpredicates:@[_predicate, predicate]];
  }

  return [[QKQuerySet alloc] initWithManagedObjectContext:_managedObjectContext entityDescription:_entityDescription predicate:predicate sortDescriptors:_sortDescriptors range:self.range];
}

- (instancetype)filter:(NSPredicate *)predicate {
  if (_predicate) {
    predicate = [[NSCompoundPredicate alloc] initWithType:NSAndPredicateType subpredicates:@[_predicate, predicate]];
  }

  return [[QKQuerySet alloc] initWithManagedObjectContext:_managedObjectContext entityDescription:_entityDescription predicate:predicate sortDescriptors:_sortDescriptors range:self.range];
}

@end

@implementation QKQuerySet (SingleObject)

- (NSManagedObject *)object:(NSError **)error {
  NSManagedObject *managedObject;
  NSArray *array;

  if (_resultsCache) {
    array = _resultsCache;
  } else {
    NSFetchRequest *fetchRequest = [self fetchRequest];
    fetchRequest.fetchBatchSize = 1; // Only request one

    array = [self.managedObjectContext executeFetchRequest:fetchRequest error:error];
  }

  NSUInteger count = [array count];

  if (count == 1) {
    managedObject = [array firstObject];
  } else if ((count > 1) && error != nil) {
    NSString *errorDescription = @"Find object in fetch request failed, should only result in a single result.";
    *error = [NSError errorWithDomain:QKQuerySetErrorDomain code:0 userInfo:@{ NSLocalizedDescriptionKey: errorDescription }];
  }

  return managedObject;
}

- (NSManagedObject *)firstObject:(NSError **)error {
  NSManagedObject *managedObject;

  if (_resultsCache) {
    managedObject = [_resultsCache firstObject];
  } else {
    NSFetchRequest *fetchRequest = [self fetchRequest];
    [fetchRequest setFetchLimit:1];

    NSArray *array = [self.managedObjectContext executeFetchRequest:fetchRequest error:error];
    managedObject = [array firstObject];
  }

  return managedObject;
}

- (NSManagedObject *)lastObject:(NSError **)error {
  NSManagedObject *managedObject;

  if (_resultsCache) {
    managedObject = [_resultsCache lastObject];
  } else {
    NSFetchRequest *fetchRequest = [self fetchRequest];
    NSArray *array = [self.managedObjectContext executeFetchRequest:fetchRequest error:error];
    managedObject = [array lastObject];
  }

  return managedObject;
}

@end

@implementation NSManagedObject (QKQuerySet)

+ (NSString *)entityName {
  return NSStringFromClass([self class]);
}

+ (QKQuerySet *)querySetWithManagedObjectContext:(NSManagedObjectContext *)context {
  NSEntityDescription *entityDescription = [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:context];
  return [[QKQuerySet alloc] initWithManagedObjectContext:context entityDescription:entityDescription];
}

@end
