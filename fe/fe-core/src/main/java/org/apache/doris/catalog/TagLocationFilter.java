// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package org.apache.doris.catalog;

import org.apache.doris.resource.Tag;

import com.google.common.collect.Lists;
import com.google.common.collect.Sets;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

public class TagLocationFilter {
    public static TagLocationFilter NO_FILTER = new TagLocationFilter(Sets.newHashSet(), Sets.newHashSet());

    private static Map<String, TagLocationFilter> FILTER_MAP = new ConcurrentHashMap<>();
    private Set<String> tagLocations;
    private Set<Tag> tags;

    private TagLocationFilter(Set<String> tagLocations, Set<Tag> tags) {
        this.tagLocations = Collections.unmodifiableSet(tagLocations);
        this.tags = Collections.unmodifiableSet(tags);
    }

    public boolean containsBackend(String beTag) {
        if (this == NO_FILTER) {
            return true;
        }
        return tagLocations.contains(beTag);
    }

    public boolean containsBackend(String beTag, boolean reverse) {
        if (this == NO_FILTER) {
            return true;
        }
        return tagLocations.contains(beTag) ^ reverse;
    }

    public Set<Tag> getTags() {
        return tags;
    }

    public String toTagLocationConfig() {
        if (this == NO_FILTER) {
            return "";
        }
        return String.join(",", tagLocations);
    }

    @Override
    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (obj instanceof TagLocationFilter) {
            TagLocationFilter other = (TagLocationFilter) obj;
            return tagLocations.equals(other.tagLocations);
        }
        return false;
    }

    public static TagLocationFilter createTagLocationFilter(Set<String> tagLocations, Set<Tag> tags) {
        if (tagLocations == null || tagLocations.isEmpty()) {
            return NO_FILTER;
        }
        List<String> locations = Lists.newArrayList(tagLocations);
        String key = locations.stream().sorted().collect(Collectors.joining(""));
        if (FILTER_MAP.containsKey(key)) {
            return FILTER_MAP.get(key);
        }
        TagLocationFilter filter = new TagLocationFilter(tagLocations, tags);
        TagLocationFilter old = FILTER_MAP.putIfAbsent(key, filter);
        if (old != null) {
            return old;
        }
        return filter;
    }
}
